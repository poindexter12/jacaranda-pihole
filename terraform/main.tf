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
      source = "Telmate/proxmox"
      # Version controlled by root module lockfile
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

# ============================================================================
# Proxmox HA Management (PVE 9+ Affinity Rules)
# ============================================================================
# Adds LXCs to Proxmox HA and creates anti-affinity rules to keep
# HA pairs on separate nodes during failover.
#
# PVE 9 replaced HA groups with affinity rules:
# - Node affinity: which nodes can host a resource (optional)
# - Resource affinity: keep resources together (positive) or apart (negative)

resource "null_resource" "ha_add" {
  for_each = var.ha_enabled ? var.instances : {}

  triggers = {
    lxc_id = proxmox_lxc.pihole[each.key].id
    node   = each.value.node
    vmid   = each.value.vmid
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Adding ct:${each.value.vmid} to Proxmox HA ==="
      ssh root@${each.value.node}.lan "ha-manager add ct:${each.value.vmid} --state started 2>/dev/null || true"
    EOT
  }

  # Remove from HA before destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ssh root@${self.triggers.node}.lan "ha-manager remove ct:${self.triggers.vmid} 2>/dev/null || true"
    EOT
  }

  depends_on = [null_resource.sign_host_cert]
}

# Create anti-affinity rules to keep HA pairs on separate nodes
# Each group in ha_anti_affinity_groups creates a separate rule
locals {
  # Convert anti-affinity groups to a map for for_each
  # Key: index, Value: {name: rule-name, resources: "ct:XXX,ct:YYY"}
  anti_affinity_rules = {
    for idx, group in var.ha_anti_affinity_groups : idx => {
      name = "pihole-${idx}-anti-affinity"
      resources = join(",", [
        for instance_name in group : "ct:${var.instances[instance_name].vmid}"
      ])
    }
  }
}

resource "null_resource" "ha_anti_affinity" {
  for_each = var.ha_enabled && length(var.ha_anti_affinity_groups) > 0 ? local.anti_affinity_rules : {}

  triggers = {
    rule_name = each.value.name
    resources = each.value.resources
    # Use first instance's node for SSH (rules are cluster-wide)
    node = var.instances[var.ha_anti_affinity_groups[each.key][0]].node
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Creating anti-affinity rule: ${each.value.name} ==="
      echo "    Resources: ${each.value.resources}"

      # Check if rule exists, create or update
      if ssh root@${self.triggers.node}.lan "ha-manager rules status resource-affinity ${each.value.name}" >/dev/null 2>&1; then
        echo "    Rule exists, updating..."
        ssh root@${self.triggers.node}.lan "ha-manager rules set resource-affinity ${each.value.name} --resources ${each.value.resources}"
      else
        echo "    Creating new rule..."
        ssh root@${self.triggers.node}.lan "ha-manager rules add resource-affinity ${each.value.name} --affinity negative --resources ${each.value.resources}"
      fi
    EOT
  }

  # Remove rule before destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ssh root@${self.triggers.node}.lan "ha-manager rules remove resource-affinity ${self.triggers.rule_name} 2>/dev/null || true"
    EOT
  }

  depends_on = [null_resource.ha_add]
}
