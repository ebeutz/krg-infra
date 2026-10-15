# Pre-IaC leftovers, declared ONLY so they can be adopted (imports.tf) and then
# destroyed through IaC rather than deleted by hand. Flip var.adopt_legacy to false
# after the adoption apply (README step 6); that apply removes all three. Then this
# file and the matching import blocks can go.

# ether1 is the WAN uplink; defconf left it as a (disabled) LAN bridge member.
resource "routeros_interface_bridge_port" "legacy_wan" {
  count     = var.adopt_legacy ? 1 : 0
  bridge    = routeros_interface_bridge.lan.name
  interface = local.wan_interface
  disabled  = true
  comment   = "defconf"
}

# ether1 also has a static address + static default route (ip.tf); a DHCP client on
# the same port can add a second address and a competing default route.
resource "routeros_ip_dhcp_client" "legacy_wan" {
  count     = var.adopt_legacy ? 1 : 0
  interface = local.wan_interface
}

# A DHCP network for 0.0.0.0/24 with gateway 0.0.0.0 — matches no pool; noise.
resource "routeros_ip_dhcp_server_network" "legacy_bogus" {
  count   = var.adopt_legacy ? 1 : 0
  address = "0.0.0.0/24"
  gateway = "0.0.0.0"
  netmask = 24
}
