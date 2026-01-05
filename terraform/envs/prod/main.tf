# ============================================================================
# Pi-hole Production Environment
# ============================================================================
# 4 LXC instances: 2 standard + 2 restricted, primary/secondary pairs.
#
# VMID Allocation: 4-digit TSSS pattern (1xxx = LXC, last 3 digits = IP octet)
# - All instances migrated to 4-digit VMIDs: 1020-1023
# Reference: .claude/skills/vmid-allocation.md

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
# VMID Allocation Reference
# ============================================================================
# Import centralized VMID ranges for validation.

module "vmid" {
  source = "../../../../../infrastructure/terraform/modules/vmid-ranges"
}

# Validate all VMIDs are in LXC range (1001-1254)
check "vmid_allocation" {
  assert {
    condition = alltrue([
      for name, inst in local.pihole_instances :
      contains(module.vmid.validate.lxc, inst.vmid)
    ])
    error_message = "One or more VMIDs are outside the LXC allocation range (1001-1254). See .claude/skills/vmid-allocation.md"
  }
}

locals {
  # Define instances here for validation, then pass to module
  pihole_instances = {
    # Standard profile - general ad blocking
    "dns-standard-primary" = {
      vmid          = 1020 # 4-digit TSSS: 1000 + 20 → IP .20
      node          = "joseph"
      dns_ip        = "192.168.1.20"
      mgmt_ip       = "192.168.5.20"
      transfer_ip   = "192.168.11.20"
      profile       = "standard"
      role          = "primary"
      startup_order = 1
    }
    "dns-standard-secondary" = {
      vmid          = 1021 # 4-digit TSSS: 1000 + 21 → IP .21
      node          = "maxwell"
      dns_ip        = "192.168.1.21"
      mgmt_ip       = "192.168.5.21"
      transfer_ip   = "192.168.11.21"
      profile       = "standard"
      role          = "secondary"
      startup_order = 2
    }

    # Restricted profile - stricter blocking (e.g., kids network)
    # 4-digit TSSS: 1022 (primary), 1023 (secondary)
    "dns-restricted-primary" = {
      vmid          = 1022 # 4-digit TSSS: 1000 + 22 → IP .22
      node          = "joseph"
      dns_ip        = "192.168.1.22"
      mgmt_ip       = "192.168.5.22"
      transfer_ip   = "192.168.11.22"
      profile       = "restricted"
      role          = "primary"
      startup_order = 3
    }
    "dns-restricted-secondary" = {
      vmid          = 1023 # 4-digit TSSS: 1000 + 23 → IP .23
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

  env            = "prod"
  vlans          = local.base.vlans
  ssh_public_key = local.base.ssh_public_key
  onboot         = true # Auto-start on Proxmox boot

  # Instances defined in locals for VMID validation
  instances = local.pihole_instances
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

output "transfer_ips" {
  description = "Transfer/storage network IPs"
  value       = module.pihole.transfer_ips
}

output "cname_entries" {
  description = "CNAME entries for .lan layer and bare names"
  value       = module.pihole.cname_entries
}
