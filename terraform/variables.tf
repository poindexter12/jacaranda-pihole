# ============================================================================
# Pi-hole LXC Module Variables
# ============================================================================

# ============================================================================
# REQUIRED - From Base Infrastructure
# ============================================================================

variable "vlans" {
  description = "VLAN configuration map (from base infrastructure)"
  type = map(object({
    id      = number
    bridge  = string
    network = string
    gateway = string
    domain  = string
    mtu     = number
  }))
}

variable "ssh_public_key" {
  description = "SSH public key content for root access"
  type        = string
}

# ============================================================================
# REQUIRED - Instance Configuration
# ============================================================================

variable "instances" {
  description = "Map of Pi-hole instances to create"
  type = map(object({
    vmid          = number
    node          = string
    dns_ip        = string
    mgmt_ip       = string
    transfer_ip   = string
    profile       = string           # "standard" or "restricted"
    role          = string           # "primary" or "secondary"
    startup_order = optional(number) # Startup priority (lower = earlier)
  }))
}

variable "env" {
  description = "Environment name (test, prod)"
  type        = string
}

# ============================================================================
# OPTIONAL - LXC Configuration
# ============================================================================

variable "lxc_template" {
  description = "LXC template to use"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "lxc_cores" {
  description = "Number of CPU cores per LXC"
  type        = number
  default     = 2
}

variable "lxc_memory" {
  description = "Memory in MB per LXC"
  type        = number
  default     = 1024
}

variable "lxc_disk_size" {
  description = "Root filesystem size per LXC"
  type        = string
  default     = "8G"
}

variable "lxc_storage" {
  description = "Storage pool for LXC root filesystem"
  type        = string
  default     = "local-lvm"
}

variable "dns_server" {
  description = "DNS server for LXCs during bootstrap"
  type        = string
  default     = "1.1.1.1"
}

variable "search_domain" {
  description = "Search domain for LXCs"
  type        = string
  default     = "home.arpa"
}

variable "onboot" {
  description = "Start LXC on Proxmox boot"
  type        = bool
  default     = true
}
