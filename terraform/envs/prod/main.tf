# ============================================================================
# Pi-hole Production Environment
# ============================================================================
# 4 LXC instances: 2 standard + 2 restricted, primary/secondary pairs.

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc04"
    }
    pihole = {
      source  = "registry.terraform.io/poindexter12/pihole"
      version = ">= 1.0.0"
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

# Pi-hole DNS provider (self-referential - Pi-hole manages its own DNS entries)
variable "pihole_password" {
  description = "Pi-hole admin password for DNS API"
  type        = string
  sensitive   = true
}

provider "pihole" {
  url      = "http://192.168.5.20"
  password = var.pihole_password
}

# ============================================================================
# Pi-hole Module
# ============================================================================

module "pihole" {
  source = "../.."

  env            = "prod"
  vlans          = local.base.vlans
  ssh_public_key = local.base.ssh_public_key
  onboot         = true # Auto-start on Proxmox boot

  instances = {
    # Standard profile - general ad blocking
    "dns-standard-primary" = {
      vmid          = 120
      node          = "joseph"
      dns_ip        = "192.168.1.20"
      mgmt_ip       = "192.168.5.20"
      transfer_ip   = "192.168.11.20"
      profile       = "standard"
      role          = "primary"
      startup_order = 1
    }
    "dns-standard-secondary" = {
      vmid          = 121
      node          = "maxwell"
      dns_ip        = "192.168.1.21"
      mgmt_ip       = "192.168.5.21"
      transfer_ip   = "192.168.11.21"
      profile       = "standard"
      role          = "secondary"
      startup_order = 2
    }

    # Restricted profile - stricter blocking (e.g., kids network)
    "dns-restricted-primary" = {
      vmid          = 122
      node          = "joseph"
      dns_ip        = "192.168.1.22"
      mgmt_ip       = "192.168.5.22"
      transfer_ip   = "192.168.11.22"
      profile       = "restricted"
      role          = "primary"
      startup_order = 3
    }
    "dns-restricted-secondary" = {
      vmid          = 123
      node          = "maxwell"
      dns_ip        = "192.168.1.23"
      mgmt_ip       = "192.168.5.23"
      transfer_ip   = "192.168.11.23"
      profile       = "restricted"
      role          = "secondary"
      startup_order = 4
    }
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "instances" {
  description = "Production Pi-hole instances"
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

output "primary_instances" {
  description = "Primary instances (nebula-sync source)"
  value       = module.pihole.primary_instances
}

output "secondary_instances" {
  description = "Secondary instances (nebula-sync target)"
  value       = module.pihole.secondary_instances
}

# ============================================================================
# DNS Records (Pi-hole)
# ============================================================================
# Self-referential: Pi-hole instances register themselves in Pi-hole DNS

resource "pihole_dns_record" "pihole_trusted" {
  for_each = module.pihole.dns_ips

  domain = "${each.key}.trusted"
  ip     = each.value
}

resource "pihole_dns_record" "pihole_mgmt" {
  for_each = module.pihole.mgmt_ips

  domain = "${each.key}.mgmt"
  ip     = each.value
}

resource "pihole_dns_record" "pihole_storage" {
  for_each = module.pihole.transfer_ips

  domain = "${each.key}.storage"
  ip     = each.value
}
