locals {
  # Shared source of truth (terraform/README.md) — never duplicate these values here.
  trusted = jsondecode(file("${path.module}/../../nix/networks/trusted.json"))

  # krg-deploy is the only host that drives the REST API; looked up by its comment so
  # an IP change in trusted.json carries over. one() fails loudly if it disappears.
  deploy_cidr = one([for m in local.trusted.ipsets.machines : m.cidr if startswith(m.comment, "krg-deploy.")])

  # Who may reach SSH/Winbox/www-ssl from the WAN side: admins' remotes + krg-deploy.
  mgmt_cidrs = distinct(concat([for o in local.trusted.ipsets.ops : o.cidr], [local.deploy_cidr]))
  mgmt_list  = "krg-mgmt"

  wan_interface = "ether1"
  wan_address   = "132.239.17.56/24"
  wan_gateway   = "132.239.17.1"

  lan_address = "192.168.1.1/24"
  lan_cidr    = "192.168.1.0/24"
  lan_gateway = "192.168.1.1"
  dhcp_range  = "192.168.1.100-192.168.1.245"

  # CRS328-24P-4S+: ether1 is the WAN uplink; everything else is bridged LAN.
  lan_ports = concat(
    [for i in range(2, 25) : "ether${i}"],
    [for i in range(1, 5) : "sfp-sfpplus${i}"],
  )
}
