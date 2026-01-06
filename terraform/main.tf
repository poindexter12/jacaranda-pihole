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

# ============================================================================
# Sign Host Certificates
# ============================================================================
# Signs host cert after LXC creation. Uses pct exec via Proxmox node instead
# of SSH - no SSH to the LXC required during signing.
# Future: Issue #83 tracks moving to ACME-SSH for non-SSH-based signing.

resource "null_resource" "sign_host_cert" {
  for_each   = var.instances
  depends_on = [proxmox_lxc.pihole]

  triggers = {
    lxc_id = proxmox_lxc.pihole[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NODE="${each.value.node}"
      CTID="${each.value.vmid}"

      echo "=== Waiting for ${each.key} to be ready ==="
      for i in $(seq 1 30); do
        if ssh root@$NODE.lan "pct exec $CTID -- echo ready" 2>/dev/null; then
          break
        fi
        echo "  Attempt $i/30 - waiting..."
        sleep 5
      done

      echo "=== Fetching host public key from ${each.key} ==="
      HOST_PUBKEY=$(ssh root@$NODE.lan "pct exec $CTID -- cat /etc/ssh/ssh_host_ed25519_key.pub")

      echo "=== Signing certificate on step-ca ==="
      HOST_IPS=$(ssh root@$NODE.lan "pct exec $CTID -- hostname -I | tr ' ' ','")

      PRINCIPALS="${each.key},${each.key}.lan,${each.key}.mgmt,${each.key}.trusted,${each.key}.transfer,$${HOST_IPS%,}"

      echo "$HOST_PUBKEY" | ssh root@step-ca.lan "cat > /tmp/${each.key}.pub"

      ssh root@step-ca.lan "
        set -e
        export OP_SERVICE_ACCOUNT_TOKEN=\$(cat /var/lib/step-ca/secrets/.op_token)
        KEY_FILE=/var/lib/step-ca/secrets/.ephemeral_ca_key.${each.key}
        op read 'op://SSH-CA/ssh-ca-host-virtual/private_key' > \$KEY_FILE
        chmod 600 \$KEY_FILE
        ssh-keygen -s \$KEY_FILE -I ${each.key} -h -n $PRINCIPALS -V +52w /tmp/${each.key}.pub
        rm -f \$KEY_FILE
      "

      SIGNED_CERT=$(ssh root@step-ca.lan "cat /tmp/${each.key}-cert.pub")
      ssh root@step-ca.lan "rm -f /tmp/${each.key}.pub /tmp/${each.key}-cert.pub"

      echo "=== Installing certificate on ${each.key} ==="
      echo "$SIGNED_CERT" | ssh root@$NODE.lan "pct exec $CTID -- tee /etc/ssh/ssh_host_ed25519_key-cert.pub > /dev/null"
      ssh root@$NODE.lan "pct exec $CTID -- systemctl reload ssh || pct exec $CTID -- systemctl reload sshd || true"

      echo "=== ${each.key} host certificate signed and installed ==="
    EOT
  }
}
