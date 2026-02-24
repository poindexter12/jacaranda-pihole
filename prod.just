# Pi-hole Production Environment Module
#
# 4-instance HA cluster with blue-green deployment support
# - dns-standard-primary (1020) / dns-standard-secondary (1021)
# - dns-restricted-primary (1022) / dns-restricted-secondary (1023)
#
# Usage: just prod::<recipe>
#
# Examples:
#   just prod::apply             # Create 4 LXCs
#   just prod::deploy            # Deploy all (pihole + cloudflared + nebula-sync)
#   just prod::deploy-green      # Deploy secondaries first
#   just prod::deploy-blue       # Deploy primaries after verification
#   just prod::validate          # Test DNS on all 4 instances
#   just prod::validate-blue     # Test primaries only
#   just prod::validate-green    # Test secondaries only
#   just prod::upgrade-blue      # Upgrade primaries
#   just prod::upgrade-green     # Upgrade secondaries

import 'lib/infrastructure/just/terraform.just'
import 'lib/infrastructure/just/ansible.just'

# ============================================================================
# Terraform Operations
# ============================================================================

# Initialize terraform
[group('terraform')]
init: (tf-init "prod")

# Plan infrastructure changes
[group('terraform')]
plan: (tf-plan "prod")

# Apply infrastructure changes
[group('terraform')]
apply: (tf-apply "prod")

# Destroy all infrastructure
[group('terraform')]
[confirm("Destroy ALL production Pi-hole instances? This is DANGEROUS!")]
destroy: (tf-destroy "prod")

# Destroy secondary instances only (green)
[group('terraform')]
[confirm("Destroy secondary Pi-hole instances?")]
destroy-green:
    #!/usr/bin/env bash
    set -euo pipefail
    cd terraform/envs/prod
    flags="-var=encryption_passphrase=$({{ op_read }} 'op://Homelab/opentofu/password')"
    printf '%b→ Destroying secondaries (green)%b\n' '{{ YELLOW }}' '{{ NC }}'
    tofu init -reconfigure $flags
    tofu destroy -auto-approve $flags \
        -target='module.pihole.proxmox_lxc.pihole["dns-standard-secondary"]' \
        -target='module.pihole.proxmox_lxc.pihole["dns-restricted-secondary"]'
    printf '%b✓ Secondaries destroyed%b\n' '{{ GREEN }}' '{{ NC }}'

# Destroy primary instances only (blue)
[group('terraform')]
[confirm("Destroy primary Pi-hole instances?")]
destroy-blue:
    #!/usr/bin/env bash
    set -euo pipefail
    cd terraform/envs/prod
    flags="-var=encryption_passphrase=$({{ op_read }} 'op://Homelab/opentofu/password')"
    printf '%b→ Destroying primaries (blue)%b\n' '{{ YELLOW }}' '{{ NC }}'
    tofu init -reconfigure $flags
    tofu destroy -auto-approve $flags \
        -target='module.pihole.proxmox_lxc.pihole["dns-standard-primary"]' \
        -target='module.pihole.proxmox_lxc.pihole["dns-restricted-primary"]'
    printf '%b✓ Primaries destroyed%b\n' '{{ GREEN }}' '{{ NC }}'

# ============================================================================
# Ansible Operations
# ============================================================================

# Deploy Pi-hole to all instances (pihole + cloudflared + nebula-sync)
[group('deploy')]
deploy: fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-prod/webpassword')
    cd ansible
    printf '%b→ Deploying Pi-hole to all production instances%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-lxc.yaml -e "pihole_password=$pw"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-cloudflared.yaml
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/nebula-sync.yaml -e "pihole_password=$pw"
    printf '%b✓ Production deployment complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Deploy to secondaries first (green) - full stack
[group('deploy')]
deploy-green: fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-prod/webpassword')
    cd ansible
    printf '%b→ Deploying to secondaries (green)%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-lxc.yaml --limit pihole_secondary \
        -e "pihole_password=$pw"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-cloudflared.yaml --limit pihole_secondary
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/nebula-sync.yaml --limit pihole_secondary \
        -e "pihole_password=$pw"
    printf '%b✓ Secondary deployment complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Deploy to primaries after verification (blue) - no nebula-sync
[group('deploy')]
deploy-blue: fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-prod/webpassword')
    cd ansible
    printf '%b→ Deploying to primaries (blue)%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-lxc.yaml --limit pihole_primary \
        -e "pihole_password=$pw"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-cloudflared.yaml --limit pihole_primary
    printf '%b✓ Primary deployment complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Register DNS entries for production Pi-holes
[group('deploy')]
dns: (ansible-run "prod" "playbooks/pihole-dns-self.yaml")

# ============================================================================
# Upgrades
# ============================================================================

# Check versions without upgrading
[group('upgrade')]
upgrade-check: (ansible-run "prod" "playbooks/pihole-upgrade.yaml" "--tags check")

# Upgrade primaries (blue) - step 1
[group('upgrade')]
upgrade-blue:
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-prod/webpassword')
    cd ansible
    printf '%b→ Upgrading primaries (blue)%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-upgrade.yaml --limit pihole_primary \
        -e "pihole_password=$pw"
    printf '%b✓ Primary upgrade complete%b\n' '{{ GREEN }}' '{{ NC }}'
    printf '\n%bVerify primaries are working, then run: just prod::upgrade-green%b\n' '{{ YELLOW }}' '{{ NC }}'

# Upgrade secondaries (green) - step 2
[group('upgrade')]
upgrade-green:
    #!/usr/bin/env bash
    set -euo pipefail
    pw=$({{ op_read }} 'op://Homelab/pihole-prod/webpassword')
    cd ansible
    printf '%b→ Upgrading secondaries (green)%b\n' '{{ CYAN }}' '{{ NC }}'
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} -i inventory/prod.yaml \
        playbooks/pihole-upgrade.yaml --limit pihole_secondary \
        -e "pihole_password=$pw"
    printf '%b✓ Secondary upgrade complete%b\n' '{{ GREEN }}' '{{ NC }}'

# ============================================================================
# Validation
# ============================================================================

# Validate DNS resolution on all 4 instances
[group('validate')]
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== DNS Resolution Test (all 4 instances) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    for ip in 192.168.1.20 192.168.1.21 192.168.1.22 192.168.1.23; do
        printf 'Testing %s: ' "$ip"
        result=$(dig @$ip google.com +short +time=2 +tries=1 2>/dev/null | head -1) || result=""
        if [[ -n "$result" ]]; then
            printf '%b%s ✓%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done

# Test local DNS records (A records and CNAMEs)
[group('validate')]
validate-local:
    #!/usr/bin/env bash
    set -euo pipefail
    primary_ip="192.168.1.20"
    printf '%b=== Local DNS Records (via primary %s) ===%b\n' '{{ BOLD }}' "$primary_ip" '{{ NC }}'
    printf '%bA records (.trusted network):%b\n' '{{ CYAN }}' '{{ NC }}'
    for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do
        result=$(dig @$primary_ip $host.trusted +short 2>/dev/null | head -1) || result=""
        printf '  %s.trusted: ' "$host"
        if [[ -n "$result" ]]; then
            printf '%b%s%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done
    printf '\n%bA records (.mgmt network):%b\n' '{{ CYAN }}' '{{ NC }}'
    for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do
        result=$(dig @$primary_ip $host.mgmt +short 2>/dev/null | head -1) || result=""
        printf '  %s.mgmt: ' "$host"
        if [[ -n "$result" ]]; then
            printf '%b%s%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done
    printf '\n%bCNAME records (naked hostname → .trusted):%b\n' '{{ CYAN }}' '{{ NC }}'
    for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do
        result=$(dig @$primary_ip $host +short 2>/dev/null | head -1) || result=""
        printf '  %s: ' "$host"
        if [[ -n "$result" ]]; then
            printf '%b%s%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done

# Test primaries only (blue - .20, .22)
[group('validate')]
validate-blue:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== DNS Resolution Test (BLUE/primaries) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    for ip in 192.168.1.20 192.168.1.22; do
        printf 'Testing %s: ' "$ip"
        result=$(dig @$ip google.com +short +time=2 +tries=1 2>/dev/null | head -1) || result=""
        if [[ -n "$result" ]]; then
            printf '%b%s ✓%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done

# Test secondaries only (green - .21, .23)
[group('validate')]
validate-green:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== DNS Resolution Test (GREEN/secondaries) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    for ip in 192.168.1.21 192.168.1.23; do
        printf 'Testing %s: ' "$ip"
        result=$(dig @$ip google.com +short +time=2 +tries=1 2>/dev/null | head -1) || result=""
        if [[ -n "$result" ]]; then
            printf '%b%s ✓%b\n' '{{ GREEN }}' "$result" '{{ NC }}'
        else
            printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi
    done

# Preflight: DNS and SSH connectivity
[private]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Verify prod (preflight) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    hosts="dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary"
    printf '%b--- DNS ---%b\n' '{{ CYAN }}' '{{ NC }}'
    for h in $hosts; do
        printf '%s.lan: ' "$h"
        dig +short $h.lan 2>/dev/null || printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
    done
    printf '%b--- SSH ---%b\n' '{{ CYAN }}' '{{ NC }}'
    for h in $hosts; do
        printf '%s.lan: ' "$h"
        ssh -o BatchMode=yes -o ConnectTimeout=5 root@$h.lan hostname 2>/dev/null || printf '%bFAIL%b\n' '{{ RED }}' '{{ NC }}'
    done

# ============================================================================
# Workflows
# ============================================================================

# Full deployment: apply + wait + deploy
[group('workflow')]
full: apply
    @echo "Waiting 30s for LXCs to be ready..."
    @sleep 30
    just prod::deploy

# ============================================================================
# Private Helpers
# ============================================================================

# Fetch packages via ansible/justfile
[private]
fetch:
    @cd ansible && just fetch
