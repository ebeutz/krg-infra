resource "routeros_ip_address" "wan" {
  address   = local.wan_address
  interface = local.wan_interface
}

resource "routeros_ip_address" "lan" {
  address   = local.lan_address
  interface = routeros_interface_bridge.lan.name
}

resource "routeros_ip_route" "default" {
  dst_address = "0.0.0.0/0"
  gateway     = local.wan_gateway
  distance    = 1
}

resource "routeros_ip_pool" "lan" {
  name   = "dhcp"
  ranges = [local.dhcp_range]
}

resource "routeros_ip_dhcp_server" "lan" {
  name         = "dhcp1"
  interface    = routeros_interface_bridge.lan.name
  address_pool = routeros_ip_pool.lan.name
  disabled     = false
}

resource "routeros_ip_dhcp_server_network" "lan" {
  address = local.lan_cidr
  gateway = local.lan_gateway
  netmask = 24
}

resource "routeros_ip_firewall_nat" "masquerade" {
  chain              = "srcnat"
  action             = "masquerade"
  out_interface_list = routeros_interface_list.this["WAN"].name
}

resource "routeros_ip_dns" "this" {
  servers = ["1.1.1.1", "1.0.0.1"]
  # Explicit: the router must never be an open resolver on its public address.
  allow_remote_requests = false
}
