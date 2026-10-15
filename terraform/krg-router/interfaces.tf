resource "routeros_interface_bridge" "lan" {
  name      = "bridge"
  admin_mac = "08:55:31:AE:43:7A"
  auto_mac  = false
  comment   = "defconf"
}

resource "routeros_interface_bridge_port" "lan" {
  for_each  = toset(local.lan_ports)
  bridge    = routeros_interface_bridge.lan.name
  interface = each.key
  comment   = "defconf"
}

resource "routeros_interface_list" "this" {
  for_each = toset(["WAN", "LAN"])
  name     = each.key
}

resource "routeros_interface_list_member" "wan" {
  list      = routeros_interface_list.this["WAN"].name
  interface = local.wan_interface
}

resource "routeros_interface_list_member" "lan" {
  list      = routeros_interface_list.this["LAN"].name
  interface = routeros_interface_bridge.lan.name
}
