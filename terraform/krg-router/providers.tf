# terraform/krg-router — the MikroTik CRS328-24P-4S+ lab router (RouterOS 7).
#
# ADR 0007's rule applied: RouterOS exposes a full CRUD REST API, so its config is a
# real OpenTofu target (state + drift detection), not command-convergence in Ansible.
#
# AUTH — the REST API over www-ssl (RouterOS >= 7.1; the v6 binary API is NOT used).
# The router's TLS cert is a long-lived self-signed cert created at bootstrap; its
# public half is PINNED in git as router-server.crt (same posture as
# terraform/incus/krg-nat-server.crt — a reviewed pin, not trust-on-first-use). The
# password comes from OpenBao (secret/krg-deploy/krg-router, already readable by the
# krg-deploy AppRole) via TF_VAR_routeros_password — deploy/deploy-tofu.sh
# materializes it; it is a provider argument, so it never lands in state.
#
# NOT IN TOFU_TARGETS. Merging this applies nothing. The router is adopted by hand
# (README.md "Bring-up"); only after a plan shows no surprise changes does it join the
# unattended deploy. A bad firewall apply here cuts the deploy path's only route in.

terraform {
  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.99"
    }
  }
  required_version = ">= 1.11.0"
}

provider "routeros" {
  hosturl        = "https://${var.router_host}"
  username       = var.routeros_username
  password       = var.routeros_password
  ca_certificate = "${path.module}/router-server.crt"
  insecure       = false
}
