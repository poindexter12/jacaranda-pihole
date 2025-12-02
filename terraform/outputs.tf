# ============================================================================
# Pi-hole LXC Module Outputs
# ============================================================================

output "instances" {
  description = "Map of created Pi-hole instances"
  value = {
    for name, lxc in proxmox_lxc.pihole : name => {
      vmid        = lxc.vmid
      hostname    = lxc.hostname
      node        = lxc.target_node
      dns_ip      = var.instances[name].dns_ip
      mgmt_ip     = var.instances[name].mgmt_ip
      transfer_ip = var.instances[name].transfer_ip
      profile     = var.instances[name].profile
      role        = var.instances[name].role
    }
  }
}

output "mgmt_ips" {
  description = "Map of hostname to management IP"
  value = {
    for name, config in var.instances : name => config.mgmt_ip
  }
}

output "dns_ips" {
  description = "Map of hostname to DNS IP"
  value = {
    for name, config in var.instances : name => config.dns_ip
  }
}

output "transfer_ips" {
  description = "Map of hostname to transfer/storage IP"
  value = {
    for name, config in var.instances : name => config.transfer_ip
  }
}

output "primary_instances" {
  description = "Primary Pi-hole instances (for nebula-sync source)"
  value = {
    for name, config in var.instances : name => config.mgmt_ip
    if config.role == "primary"
  }
}

output "secondary_instances" {
  description = "Secondary Pi-hole instances (for nebula-sync target)"
  value = {
    for name, config in var.instances : name => {
      mgmt_ip     = config.mgmt_ip
      transfer_ip = config.transfer_ip
      profile     = config.profile
    }
    if config.role == "secondary"
  }
}
