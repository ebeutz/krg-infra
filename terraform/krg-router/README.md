# terraform/krg-router — MikroTik lab router

One target of the [`terraform/`](../README.md) OpenTofu layer. Manages the
**MikroTik CRS328-24P-4S+** (WAN `ether1` = `132.239.17.56/24`, NAT'd LAN
`192.168.1.0/24` on `bridge`) with the
[`terraform-routeros/routeros`](https://registry.terraform.io/providers/terraform-routeros/routeros)
provider over the RouterOS 7 REST API.

> **Why OpenTofu, not Ansible:** [ADR 0007](../../docs/adr/0007-dsm-config-ansible-not-terraform.md)'s
> rule: Terraform for things with a CRUD API, Ansible for appliances with only a
> CLI. RouterOS is the opposite of DSM: every `/menu add …` line in an export is a
> provider resource, so `tofu plan` gives real drift detection.

> **Not in `TOFU_TARGETS`.** Merging this target applies nothing. It joins the
> unattended deploy only at bring-up step 8, after a hand-run plan shows no
> surprises. The router's management address is the address CD reaches it through,
> so one bad firewall apply cuts the deploy path off.

## What's managed

| File | What |
|---|---|
| `interfaces.tf` | `bridge` (pinned admin MAC), LAN bridge ports `ether2-24` + `sfp-sfpplus1-4`, `WAN`/`LAN` interface lists |
| `ip.tf` | WAN/LAN addresses, static default route, DHCP pool/server/network, srcnat masquerade, DNS (no remote requests) |
| `firewall.tf` | `krg-mgmt` address list (from `nix/networks/trusted.json`: `ops` + krg-deploy), ordered input/forward filter |
| `hardening.tf` | `/ip service` (telnet/ftp/www/api/api-ssl **off**; ssh/winbox/www-ssl pinned to admin sources), MAC-server + neighbor discovery LAN-only, IPv6 off, identity, clock |
| `legacy.tf` | Three pre-IaC leftovers, declared only so they can be adopted and then destroyed through IaC (`adopt_legacy`) |
| `discover-imports.sh` | Read-only discovery: generates `imports.tf` with the live object IDs |

**Deliberately not managed here:** the `tofu` user/group (managing `/user` needs
the `policy` permission, effectively full admin; keeping it bootstrap-owned keeps
the deploy credential least-privilege), the `admin` account, and the TLS
certificate itself (tofu can't connect until the cert exists).

### What the pre-IaC config got wrong (fixed here)

1. **No `/ip firewall filter` at all on a public address.** Every stock RouterOS
   service (telnet, ftp, www, ssh, winbox, api, api-ssl) was internet-reachable,
   the same attack class as the Proxmox root-SSH dictionary attack. With no forward
   filter, any host on `132.239.17.0/24` could also route straight into the LAN
   through `.56`; NAT doesn't stop that.
2. `ether1` had a static address **and** a DHCP client (two addresses, competing
   default routes). The static one is canonical; the client is a `legacy.tf` removal.
3. A bogus `/ip dhcp-server network 0.0.0.0/24 gateway=0.0.0.0` (`legacy.tf`).
4. The disabled defconf `ether1` bridge port (`legacy.tf`).

Two flags gate the risky parts, both default-safe:

- `firewall_enforce = false`: the two terminal DROPs are created **disabled**.
- `adopt_legacy = true`: the leftovers stay declared, so they can be imported.

## Bring-up

Steps 1-2 are the one-time bootstrap (the analogue of the NAS's "Phase 1"):
the minimum by hand so that tofu can connect at all. From step 4 on, every change
is a commit.

**Break-glass throughout:** a laptop on any LAN port + Winbox over MAC (MAC-Winbox
stays allowed on `LAN` in every state of this config). Last resort: Netinstall.

### 0. Back up (off-box, never in git)

```routeros
/export show-sensitive file=pre-iac
/system backup save name=pre-iac
```

Download both. Keep them in the lab password manager, not the repo: the backup
holds password hashes.

### 1. Upgrade to RouterOS 7

v6 has no REST API; the provider's coverage is tested against v7.

```routeros
/system package update set channel=upgrade
/system package update check-for-updates
/system package update install          # reboots into 7.x; config is converted
# after it is back:
/system package update set channel=stable
/system package update install          # latest 7.x stable
/system routerboard upgrade             # then /system reboot, for the firmware
```

Re-export (`/export`) and compare with `pre-iac.rsc`. The conversion should keep
everything; the wireless security profile disappears (there's no radio).

### 2. Bootstrap the API identity + TLS

```routeros
/user group add name=tofu policy=read,write,api,rest-api
/user add name=tofu group=tofu address=137.110.161.122/32 password="<generated>"
/user set admin password="<strong — store in vaultwarden>"

/certificate add name=krg-router-tls common-name=132.239.17.56 \
    subject-alt-name=IP:132.239.17.56 key-size=prime256v1 days-valid=3650 \
    key-usage=digital-signature,key-agreement,tls-server
/certificate sign krg-router-tls
/ip service set www-ssl certificate=krg-router-tls tls-version=only-1.2 \
    address=137.110.161.122/32 disabled=no
/certificate export-certificate krg-router-tls file-name=router-server
```

Generate the tofu password with `openssl rand -base64 32` and store it before
using it. The krg-deploy AppRole can only *read*, so this needs an operator token:

```bash
bao kv put secret/krg-deploy/krg-router password='<generated>'
```

If the router is still exposed when you get here, `/ip service set telnet,ftp,www,api,api-ssl disabled=yes`
is an acceptable stopgap. `hardening.tf` declares exactly that state, so it isn't
drift.

### 3. Pin the certificate

Copy `router-server.crt` off the router into `terraform/krg-router/router-server.crt`
and commit it. `deploy-tofu.sh` skips this target until the file exists. If the
certificate is ever regenerated, refresh the pin the same way.

### 4. Discover import IDs

On krg-deploy, with the AppRole `VAULT_TOKEN` exported (or `ROS_PASSWORD`):

```bash
terraform/krg-router/discover-imports.sh > terraform/krg-router/imports.tf
```

This is read-only (REST `GET`s). It fails loudly if any object doesn't match
exactly once. Commit `imports.tf`.

### 5. Plan (by hand, against the real encrypted state)

```bash
TOFU_TARGETS=krg-router TOFU_PLAN_ONLY=1 ./deploy/deploy-tofu.sh
```

Expect:

- **Imports** for everything in `imports.tf`.
- **Creates** for the settings singletons (`ip_service`, `ip_dns`, clock,
  identity, mac-server, neighbor discovery, IPv6), the address list, the
  firewall rules, and `move_items`.
- **No destroys** and no updates on imported objects.

Any update on an imported object means the v7 conversion changed a value; fix
the `.tf` to match before applying.

### 6. Apply (by hand), then check the firewall

```bash
TOFU_TARGETS=krg-router ./deploy/deploy-tofu.sh
```

On the router, `/ip firewall filter print stats`: the `tofu: in-mgmt` rule's
counters must be climbing (that's the deploy runner and your SSH session matching
it). The two `tofu: … (staged OFF …)` drops are still disabled.

### 7. Enforce + clean up (its own PR, applied by hand)

Set `firewall_enforce = true` and `adopt_legacy = false` (defaults in
`variables.tf`). The plan must show **2 updates** (the drops become enabled) and
**3 destroys** (the `legacy.tf` objects), and nothing else. Apply with step 6's
command, then from off-campus confirm `nmap -Pn -p 21,23,80,8291,8728,8729 132.239.17.56`
shows nothing open to a non-`ops` address. After that `imports.tf` and `legacy.tf`
can be deleted.

### 8. Hand it to CD

Add `krg-router` to `TOFU_TARGETS` in the phase 3 step of
`.github/workflows/deploy.yml`. From here a merge is an apply.

## Follow-ups (own PRs)

- **Monitoring:** SNMPv3 → `snmp_exporter` (mikrotik module) on krg-prod +
  Grafana dashboard; same shape as the e4e-nas SNMP follow-up.
- **Logs:** `/system logging action` remote → Loki once ADR 0015's push endpoint exists.
- **NTP client** (`routeros_system_ntp_client`) pointed at campus NTP.
- **`.terraform.lock.hcl`:** not committed yet (the registry wasn't reachable when this
  was authored). Run `tofu providers lock -platform=linux_amd64` and commit it,
  like the sibling targets.
- **Capacity note:** the CRS328 is a switch. Routing and NAT run on its CPU, so
  throughput tops out around a few hundred Mbps. Fine for a small LAN; it isn't
  line-rate 1G/10G NAT.
