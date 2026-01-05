# ============================================================================
# Pi-hole LXC Module
# ============================================================================
# Reusable module for creating Pi-hole LXC containers on Proxmox.
# Called by envs/test and envs/prod with different instance configurations.
#
# NOTE: Provider is configured in the calling environment (envs/test or envs/prod),
# not here. The module just uses whatever provider the root module configures.

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc04" # Consistent with other services
    }
  }
}

# ============================================================================
# LXC Containers
# ============================================================================

resource "proxmox_lxc" "pihole" {
  for_each = var.instances

  # Container identification
  vmid        = each.value.vmid
  hostname    = each.key
  target_node = each.value.node

  # OS Template - Ubuntu 24.04 LXC
  ostemplate = var.lxc_template

  # Container settings
  unprivileged = true
  onboot       = var.onboot
  start        = true

  # Proxmox HA - enables container migration on node failure
  hastate = var.env == "prod" ? "started" : null

  # Startup order (if specified)
  startup = each.value.startup_order != null ? "order=${each.value.startup_order}" : null

  # Resources
  cores  = var.lxc_cores
  memory = var.lxc_memory

  # Root filesystem
  rootfs {
    storage = var.lxc_storage
    size    = var.lxc_disk_size
  }

  # Features - enable nesting for systemd compatibility
  features {
    nesting = true
  }

  # Network: eth0 - Trusted VLAN (DNS traffic)
  network {
    name   = "eth0"
    bridge = var.vlans["trusted"].bridge
    ip     = "${each.value.dns_ip}/24"
    gw     = var.vlans["trusted"].gateway
  }

  # Network: eth1 - Management VLAN (Web UI, SSH)
  network {
    name   = "eth1"
    bridge = var.vlans["mgmt"].bridge
    ip     = "${each.value.mgmt_ip}/24"
    # No gateway - default route via trusted network
  }

  # Network: eth2 - Transfer VLAN (nebula-sync replication)
  network {
    name   = "eth2"
    bridge = var.vlans["transfer"].bridge
    ip     = "${each.value.transfer_ip}/24"
    # No gateway - used only for inter-pihole sync traffic
  }

  # DNS configuration during bootstrap
  nameserver   = var.dns_server
  searchdomain = var.search_domain

  # SSH public key for root access
  ssh_public_keys = trimspace(var.ssh_public_key)

  # Tags for organization
  tags = join(",", compact([
    "pihole",
    var.env,
    "ha",
    "replicated", # DNS-based HA via multiple server entries in DHCP
    each.value.role,
    each.value.profile,
  ]))

  lifecycle {
    ignore_changes = [
      # Prevent recreation on template changes
      ostemplate,
      # Telmate provider import quirks - these aren't read back properly
      # and show as "forces replacement" even when values match
      ssh_public_keys,
      rootfs,
      features,
      network,
      start,
      cmode, # Provider tries to add default, Proxmox rejects on existing containers
    ]
  }
}
