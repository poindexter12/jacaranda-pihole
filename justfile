# Pi-hole Service (DNS)
#
# 4 production instances + 1 test instance
# Provides DNS with ad blocking via Pi-hole + cloudflared DoH
#
# Usage: just <module>::<recipe>
#
# Examples:
#   just test::full              # Create test LXC + deploy Pi-hole
#   just test::validate          # Test DNS on test instance
#   just prod::full              # Create 4 prod LXCs + deploy
#   just prod::validate          # Test DNS on all 4 instances
#   just prod::deploy-green      # Deploy to secondaries first
#   just prod::deploy-blue       # Deploy to primaries after verification

import 'lib/infrastructure/just/styles.just'
import 'lib/infrastructure/just/secrets.just'

# Module declarations
mod test
mod prod

# Show available recipes
@_default:
    just --list

# ============================================================================
# Cross-Environment Utilities
# ============================================================================

# Verify 1Password items exist
check-secrets:
    #!/usr/bin/env bash
    printf '%b─── Checking 1Password items ───%b\n' '{{ BOLD }}' '{{ NC }}'
    for env in test prod; do
        item="pihole-$env"
        echo "Pi-hole $env: op://Homelab/$item/webpassword"
        if {{ op_read }} "op://Homelab/$item/webpassword" > /dev/null 2>&1; then
            printf '%b  ✓ %s exists%b\n' '{{ GREEN }}' "$item" '{{ NC }}'
        else
            printf '%b  ✗ %s missing%b\n' '{{ RED }}' "$item" '{{ NC }}'
        fi
    done
