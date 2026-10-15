variable "router_host" {
  description = "Address the REST API is dialed on. Must be a SAN of the pinned router-server.crt."
  type        = string
  default     = "132.239.17.56"
}

variable "routeros_username" {
  description = "RouterOS account tofu authenticates as (group `tofu`: read,write,api,rest-api — created at bootstrap, not managed here)."
  type        = string
  default     = "tofu"
}

variable "routeros_password" {
  description = "Password for routeros_username. From OpenBao secret/krg-deploy/krg-router (field: password)."
  type        = string
  sensitive   = true
}

variable "identity" {
  description = "/system identity name."
  type        = string
  default     = "krg-router"
}

variable "tls_certificate" {
  description = "Name of the RouterOS certificate (created at bootstrap) that www-ssl serves; its public half is router-server.crt."
  type        = string
  default     = "krg-router-tls"
}

variable "firewall_enforce" {
  description = <<-EOT
    Enable the two terminal DROP rules (input from !LAN, new forwards from WAN that
    were not dst-NATed). Ships OFF: the first apply lands every ACCEPT rule plus these
    drops DISABLED, so you can confirm the mgmt-accept counters move before anything
    can lock the deploy path out. Flip to true in its own PR (README step 7).
  EOT
  type        = bool
  default     = false
}

variable "adopt_legacy" {
  description = <<-EOT
    Keep the three pre-IaC leftovers (disabled ether1 bridge port, the ether1 DHCP
    client, the bogus 0.0.0.0/24 DHCP network) declared so imports.tf can adopt them.
    Flip to false AFTER adoption: the next apply destroys them through IaC.
  EOT
  type        = bool
  default     = true
}
