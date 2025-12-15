# ============================================================================
# Pi-hole Test Environment
# ============================================================================
# Single test instance for validating changes before production.
# DNS records are managed separately in infrastructure/dns/

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc04"
    }
  }
}

# ============================================================================
# Base Infrastructure
# ============================================================================

data "terraform_remote_state" "base" {
  backend = "local"

  config = {
    path = "../../../../../infrastructure/terraform/terraform.tfstate"
  }
}

locals {
  base = data.terraform_remote_state.base.outputs
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "proxmox" {
  pm_api_url          = local.base.proxmox_api_url
  pm_api_token_id     = local.base.proxmox_api_token_id
  pm_api_token_secret = local.base.proxmox_api_token_secret
  pm_tls_insecure     = local.base.proxmox_tls_insecure
  pm_timeout          = 600
}

# ============================================================================
# Pi-hole Module
# ============================================================================

module "pihole" {
  source = "../.."

  env            = "test"
  vlans          = local.base.vlans
  ssh_public_key = local.base.ssh_public_key
  onboot         = false # Don't auto-start test instance

  instances = {
    "dns-test" = {
      vmid          = 1199 # 4-digit TSSS: 1000 + 199 → IP .199
      node          = "joseph"
      dns_ip        = "192.168.1.199"
      mgmt_ip       = "192.168.5.199"
      transfer_ip   = "192.168.11.199"
      profile       = "standard"
      role          = "primary"
      startup_order = null
    }
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "instances" {
  description = "Test Pi-hole instances"
  value       = module.pihole.instances
}

output "mgmt_ips" {
  description = "Management IPs for SSH/Web UI"
  value       = module.pihole.mgmt_ips
}

output "dns_ips" {
  description = "DNS IPs for client queries"
  value       = module.pihole.dns_ips
}

output "transfer_ips" {
  description = "Transfer/storage network IPs"
  value       = module.pihole.transfer_ips
}
