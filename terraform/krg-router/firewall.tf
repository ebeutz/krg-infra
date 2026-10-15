# The router had NO /ip firewall filter at all while holding a public address — every
# RouterOS service was internet-reachable, and any host on 132.239.17.0/24 could route
# straight into 192.168.1.0/24 through it. This file closes both.
#
# ORDER IS THE POLICY: each list below is in rule order, and routeros_move_items pins
# the live order to it. The terminal DROPs live in a separate resource that depends on
# the ACCEPTs, so on a fresh router they are always CREATED after (and therefore
# appended below) the mgmt accept — a parallel create can never briefly put a drop
# above the rule that admits the deploy runner. They also ship disabled
# (var.firewall_enforce).

locals {
  # Every rule is merged over this so the list has one uniform object type.
  rule_defaults = {
    connection_state     = null
    connection_nat_state = null
    protocol             = null
    dst_port             = null
    in_interface_list    = null
    src_address_list     = null
  }

  filter_rules = [for r in [
    { key = "in-established", chain = "input", action = "accept", connection_state = "established,related,untracked" },
    { key = "in-invalid", chain = "input", action = "drop", connection_state = "invalid" },
    { key = "in-icmp", chain = "input", action = "accept", protocol = "icmp" },
    { key = "in-mgmt", chain = "input", action = "accept", in_interface_list = "WAN", src_address_list = local.mgmt_list, protocol = "tcp", dst_port = "22,443,8291" },
    { key = "fwd-fasttrack", chain = "forward", action = "fasttrack-connection", connection_state = "established,related" },
    { key = "fwd-established", chain = "forward", action = "accept", connection_state = "established,related,untracked" },
    { key = "fwd-invalid", chain = "forward", action = "drop", connection_state = "invalid" },
  ] : merge(local.rule_defaults, r)]

  enforce_rules = [for r in [
    # LAN may still reach the router (DHCP, local Winbox break-glass); /ip service
    # address lists (hardening.tf) narrow what it can log in to.
    { key = "in-drop-not-lan", chain = "input", action = "drop", in_interface_list = "!LAN" },
    # The routed-into-LAN hole: nothing NEW from WAN unless a dst-nat rule sent it.
    { key = "fwd-drop-wan-new", chain = "forward", action = "drop", connection_state = "new", connection_nat_state = "!dstnat", in_interface_list = "WAN" },
  ] : merge(local.rule_defaults, r)]
}

resource "routeros_ip_firewall_addr_list" "mgmt" {
  for_each = toset(local.mgmt_cidrs)
  list     = local.mgmt_list
  address  = each.key
  comment  = "tofu: from nix/networks/trusted.json"
}

resource "routeros_ip_firewall_filter" "rule" {
  for_each             = { for r in local.filter_rules : r.key => r }
  chain                = each.value.chain
  action               = each.value.action
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
  protocol             = each.value.protocol
  dst_port             = each.value.dst_port
  in_interface_list    = each.value.in_interface_list
  src_address_list     = each.value.src_address_list
  comment              = "tofu: ${each.key}"

  depends_on = [routeros_ip_firewall_addr_list.mgmt, routeros_interface_list.this]
}

resource "routeros_ip_firewall_filter" "enforce" {
  for_each             = { for r in local.enforce_rules : r.key => r }
  chain                = each.value.chain
  action               = each.value.action
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
  protocol             = each.value.protocol
  dst_port             = each.value.dst_port
  in_interface_list    = each.value.in_interface_list
  src_address_list     = each.value.src_address_list
  disabled             = !var.firewall_enforce
  comment              = "tofu: ${each.key}${var.firewall_enforce ? "" : " (staged OFF — var.firewall_enforce)"}"

  depends_on = [routeros_ip_firewall_filter.rule]
}

resource "routeros_move_items" "filter" {
  resource_path = "/ip/firewall/filter"
  sequence = concat(
    [for r in local.filter_rules : routeros_ip_firewall_filter.rule[r.key].id],
    [for r in local.enforce_rules : routeros_ip_firewall_filter.enforce[r.key].id],
  )
}
