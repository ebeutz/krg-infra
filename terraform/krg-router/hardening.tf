# Management-plane hardening. Same attack class as the Proxmox root-SSH dictionary
# attack that started this rebuild: on a stock RouterOS every login service listens on
# every address. Here only SSH, Winbox and www-ssl stay up, each pinned to admin sources.

locals {
  # SSH + Winbox: admins (WAN side, via the firewall's krg-mgmt list) and the LAN
  # itself, so a console on the LAN is always a way back in.
  admin_sources = join(",", concat(local.mgmt_cidrs, [local.lan_cidr]))

  services_off = { telnet = 23, ftp = 21, www = 80, api = 8728, "api-ssl" = 8729 }
  services_on  = { ssh = 22, winbox = 8291 }
}

resource "routeros_ip_service" "off" {
  for_each = local.services_off
  numbers  = each.key
  port     = each.value
  disabled = true
}

resource "routeros_ip_service" "on" {
  for_each = local.services_on
  numbers  = each.key
  port     = each.value
  address  = local.admin_sources
  disabled = false
}

# The REST API tofu itself talks through. Restricting `address` here is the second
# lock alongside the firewall's in-mgmt rule; krg-deploy must stay in both.
resource "routeros_ip_service" "www_ssl" {
  numbers     = "www-ssl"
  port        = 443
  address     = local.admin_sources
  certificate = var.tls_certificate
  tls_version = "only-1.2"
  disabled    = false
}

# Layer-2 management (MAC-Winbox / MAC-Telnet) and neighbor discovery: LAN only, never
# out the public uplink.
resource "routeros_tool_mac_server" "this" {
  allowed_interface_list = routeros_interface_list.this["LAN"].name
}

resource "routeros_tool_mac_server_winbox" "this" {
  allowed_interface_list = routeros_interface_list.this["LAN"].name
}

resource "routeros_ip_neighbor_discovery_settings" "this" {
  discover_interface_list = routeros_interface_list.this["LAN"].name
}

# RouterOS 7 ships IPv6 enabled. Nothing here uses it and there is no IPv6 firewall,
# so a SLAAC address on the campus uplink would re-expose every service over v6.
resource "routeros_ipv6_settings" "this" {
  disable_ipv6 = true
}

resource "routeros_system_identity" "this" {
  name = var.identity
}

resource "routeros_system_clock" "this" {
  time_zone_name       = "America/Los_Angeles"
  time_zone_autodetect = false
}
