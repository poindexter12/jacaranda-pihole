# Pi-hole Test Environment Module
#
# Single test instance (pihole-test.lan, VMID 1199)
#
# Usage: just test::<recipe>
#
# Examples:
#   just test::apply      # Create test LXC
#   just test::deploy     # Deploy Pi-hole + cloudflared
#   just test::full       # Apply + wait + deploy
#   just test::validate   # Test DNS resolution
#   just test::verify     # Preflight: check DNS + SSH connectivity

import '../../infrastructure/just/terraform.just'
import '../../infrastructure/just/ansible.just'

# ============================================================================
# Terraform Operations
# ============================================================================

# Initialize terraform
init: (tf-init "test")

# Plan infrastructure changes
plan: (tf-plan "test")

# Apply infrastructure changes
apply: (tf-apply "test")

# Destroy infrastructure
[confirm("Destroy test Pi-hole?")]
destroy: (tf-destroy "test")

# ============================================================================
# Ansible Operations
# ============================================================================

# Deploy Pi-hole via Ansible (pihole + cloudflared)
deploy: fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-test/webpassword')
    cd ansible
    printf '%b→ Deploying Pi-hole to test%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/test.yaml \
        playbooks/pihole-lxc.yaml \
        -e "pihole_password=$pw"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/test.yaml \
        playbooks/pihole-cloudflared.yaml
    printf '%b✓ Test deployment complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Register DNS entries for test Pi-hole
dns: (ansible-run "test" "playbooks/pihole-dns-self.yaml")

# ============================================================================
# Validation
# ============================================================================

# Validate DNS resolution
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== DNS Resolution Test (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    ip="192.168.1.199"
    printf 'Testing %s: ' "$ip"
    result=$(dig @$ip google.com +short +time=2 2>/dev/null | head -1) || result=""
    if [[ -n "$result" ]]; then
        printf '%b%s ✓%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
    else
        printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

# Preflight: DNS and SSH connectivity
[private]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Verify test (preflight) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    host="pihole-test"
    printf '%b--- DNS ---%b\n' '{{ CYAN }}' '{{ NC }}'
    printf '%s.lan: ' "$host"
    dig +short $host.lan 2>/dev/null || printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
    printf '%b--- SSH ---%b\n' '{{ CYAN }}' '{{ NC }}'
    printf '%s.lan: ' "$host"
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@$host.lan hostname 2>/dev/null || printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'

# ============================================================================
# Workflows
# ============================================================================

# Full deployment: apply + wait + deploy
full: apply
    @echo "Waiting 30s for LXC to be ready..."
    @sleep 30
    just test::deploy

# ============================================================================
# Private Helpers
# ============================================================================

# Fetch packages via ansible/justfile
[private]
fetch:
    @cd ansible && just fetch
