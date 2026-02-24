# Pi-hole Service - Agent Context

## Repository Overview

**Purpose:** Pi-hole DNS with cloudflared DoH on Proxmox LXC containers
**Repository:** https://github.com/poindexter12/jacaranda-pihole
**Status:** Extracted from jacaranda-infra monorepo (Phase 41)
**Shared Libraries:** jacaranda-shared-libs v1.4.0 (submodule at lib/)

**Quick Commands:**

```bash
just --list            # Show all recipes
just test::full        # Create test LXC + deploy Pi-hole
just test::destroy     # Destroy test instance
just prod::validate    # Test production DNS
just prod::dns         # Register DNS entries for Pi-holes
just upgrade           # Update mise tools
just sync              # Sync Python dependencies
```

## Agent Boundaries

### DO (Positive Constraints)

**Development Tooling:**
- ✅ Update mise.toml for tool version upgrades (just, opentofu, uv, pre-commit)
- ✅ Update pyproject.toml for Python dependencies (Ansible, jmespath)
- ✅ Add/modify justfile recipes for new operational patterns
- ✅ Improve documentation in this file or README.md

**Infrastructure Code:**
- ✅ Modify terraform files (main.tf, variables.tf, outputs.tf) in terraform/ and terraform/envs/
- ✅ Modify Ansible playbooks, templates, and group_vars in ansible/
- ✅ Update inventory files in ansible/inventory/ for new instances or networks
- ✅ Add validation checks, preflight recipes, or diagnostic commands

**Testing & Validation:**
- ✅ Run validation recipes (just test::validate, just prod::validate)
- ✅ Test DNS queries via dig or host commands
- ✅ Verify 1Password secrets exist (just check-secrets)
- ✅ SSH to instances for diagnostics (read-only operations)

**Documentation:**
- ✅ Update this CLAUDE.md for new patterns or operational changes
- ✅ Document troubleshooting steps or common issues
- ✅ Add examples for new recipes or workflows

### DON'T (Negative Constraints)

**Hub Coordination:**
- ❌ NEVER modify jacaranda-infra hub repository (DNS aggregation, base infrastructure)
- ❌ NEVER update hub's services/ or infrastructure/ directories
- ❌ NEVER modify other service repositories (redis, postgres, netbox, etc.)

**Production Changes:**
- ❌ NEVER run `just prod::apply` or `just prod::deploy` without explicit user approval
- ❌ NEVER run `just prod::destroy` or targeted destroy commands
- ❌ NEVER modify production infrastructure without user instruction
- ❌ NEVER restart production services or LXC containers

**Infrastructure State:**
- ❌ NEVER modify terraform.tfstate files directly
- ❌ NEVER delete or rename terraform state files
- ❌ NEVER bypass Terraform for infrastructure changes (no manual Proxmox UI edits)

**Secrets & Security:**
- ❌ NEVER commit secrets or passwords to git
- ❌ NEVER hardcode 1Password references in code (use variables)
- ❌ NEVER expose secrets in logs or output

**Shared Libraries:**
- ❌ NEVER modify files in lib/ submodule (propose changes to jacaranda-shared-libs instead)
- ❌ NEVER bypass base-infra module (no direct terraform_remote_state)
- ❌ NEVER change submodule version without testing and user approval

## Skills-Only Policy

This repository is **skills-only**. Agent context lives in CLAUDE.md and related markdown documentation. DO NOT create standalone agent configuration files (.agent.json, agent.yaml, etc.).

When adding new operational patterns or troubleshooting guidance, update this CLAUDE.md file directly.

## Architecture

### Production Instances (4 LXCs, 2 profiles, HA pairs)

| Hostname | VMID | Node | Profile | Role | Trusted IP | Mgmt IP | Transfer IP |
| ---------- | ------ | ------ | --------- | ------ | ------------ | --------- | ------------- |
| dns-standard-primary | 1020 | joseph | standard | primary | 192.168.1.20 | 192.168.5.20 | 192.168.11.20 |
| dns-standard-secondary | 1021 | maxwell | standard | secondary | 192.168.1.21 | 192.168.5.21 | 192.168.11.21 |
| dns-restricted-primary | 1022 | joseph | restricted | primary | 192.168.1.22 | 192.168.5.22 | 192.168.11.22 |
| dns-restricted-secondary | 1023 | maxwell | restricted | secondary | 192.168.1.23 | 192.168.5.23 | 192.168.11.23 |

**DNS Naming Convention:**

| Pattern | Resolves To | Example |
| --------- | ------------- | --------- |
| `{hostname}.trusted` | Trusted network (192.168.1.x) | `dns-standard-primary.trusted` → 192.168.1.20 |
| `{hostname}.mgmt` | Management network (192.168.5.x) | `dns-standard-primary.mgmt` → 192.168.5.20 |
| `{hostname}.transfer` | Transfer network (192.168.11.x) | `dns-standard-primary.transfer` → 192.168.11.20 |
| `{hostname}.lan` | CNAME → .mgmt | `dns-standard-primary.lan` → 192.168.5.20 |
| `{hostname}` | CNAME → .lan | `dns-standard-primary` → `dns-standard-primary.lan` |

**Test Instance:**

| Hostname | VMID | Node | Trusted IP | Mgmt IP |
| ---------- | ------ | ------ | ------------ | --------- |
| pihole-test | 1199 | joseph | 192.168.1.199 | 192.168.5.199 |

**Network Interfaces per LXC (functional naming):**

| Interface | VLAN | Purpose |
| ----------- | ------ | --------- |
| eth0 | trusted (192.168.1.x) | DNS queries from clients |
| eth1 | mgmt (192.168.5.x) | SSH, Web UI |
| eth2 | transfer (192.168.11.x) | nebula-sync replication |

### Custom Terraform Module

Pi-hole uses a **custom LXC module** (terraform/main.tf) with features the shared LXC module doesn't support:
- 3 network interfaces (trusted, mgmt, transfer)
- SSH certificate signing via `pct exec` (run command inside container)
- Proxmox HA anti-affinity rules (keep primary/secondary pairs on different nodes)

**DO NOT migrate to shared LXC module** - the custom module is intentional and required.

## Directory Structure

```text
jacaranda-pihole/
├── justfile                    # Root recipes with mod test/prod
├── test.just                   # Test environment recipes
├── prod.just                   # Production environment recipes
├── CLAUDE.md                   # This file (agent context)
├── README.md                   # User-facing documentation
├── .gitignore
├── .gitmodules                 # Submodule configuration
├── mise.toml                   # Tool versions (just, opentofu, uv, pre-commit)
├── .mise.local.toml.example    # 1Password Connect config template
├── pyproject.toml              # Python 3.12 + Ansible 2.17
├── .envrc                      # direnv integration
├── .envrc.secrets.example      # Secrets template
├── lib/                        # Submodule: jacaranda-shared-libs v1.4.0
│   └── infrastructure/
│       ├── just/               # Shared justfile patterns
│       └── terraform/          # Shared modules (base-infra, vmid-ranges)
├── scripts/
│   ├── op-read                 # 1Password CLI wrapper
│   └── op-connect.sh           # 1Password Connect helper
├── terraform/
│   ├── main.tf                 # Custom LXC module (3 NICs, SSH cert, HA)
│   ├── variables.tf
│   ├── outputs.tf
│   └── envs/
│       ├── test/               # Test instance (VMID 1199)
│       │   ├── main.tf         # Uses base-infra module
│       │   └── backend.tf
│       └── prod/               # Production (VMIDs 1020-1023)
│           ├── main.tf         # Uses base-infra + vmid-ranges modules
│           └── backend.tf
└── ansible/
    ├── ansible.cfg
    ├── justfile                # Ansible-specific recipes
    ├── requirements.yaml       # Ansible Galaxy collections
    ├── inventory/
    │   ├── test.yaml           # Test inventory
    │   ├── prod.yaml           # Production inventory
    │   ├── group_vars -> ../group_vars
    │   └── host_vars -> ../host_vars
    ├── group_vars/
    │   ├── all.yaml
    │   └── pihole_lxc.yaml
    ├── host_vars/
    │   └── pihole-*.yaml
    ├── playbooks/
    │   ├── pihole-lxc.yaml          # Install Pi-hole
    │   ├── pihole-cloudflared.yaml  # Install cloudflared + configure
    │   ├── nebula-sync.yaml         # HA sync (secondaries only)
    │   ├── pihole-upgrade.yaml      # Blue-green upgrades
    │   └── pihole-dns-self.yaml     # Register DNS entries for Pi-holes
    ├── templates/
    └── files/
        └── docker-compose.yaml
```

## Secrets Management

**1Password Items:**
- Test: `op://Homelab/pihole-test/webpassword`
- Production: `op://Homelab/pihole-prod/webpassword`

**Verify:**

```bash
just check-secrets              # Check all secrets exist
op read 'op://Homelab/pihole-test/webpassword'   # Test password
op read 'op://Homelab/pihole-prod/webpassword'   # Prod password
```

**OpenTofu State Encryption:**
- Passphrase: `op://Homelab/opentofu/password`
- Used by terraform recipes automatically via lib/infrastructure/just/terraform.just

## Development Setup

```bash
# 1. Clone repository with submodules
git clone --recurse-submodules https://github.com/poindexter12/jacaranda-pihole.git
cd jacaranda-pihole

# 2. Install mise (if not installed)
curl https://mise.run | sh

# 3. Install tools (mise reads mise.toml)
mise install

# 4. Create local secrets (optional, for 1Password Connect)
cp .mise.local.toml.example .mise.local.toml
# Edit .mise.local.toml with your OP_CONNECT_HOST and OP_CONNECT_TOKEN

# 5. Setup Python environment
uv sync

# 6. Allow direnv (loads mise + venv)
direnv allow

# 7. Verify setup
just --list
```

## Deployment Workflows

### Test Environment

```bash
# 1. Create test LXC + deploy Pi-hole
just test::full

# 2. Verify DNS
dig @192.168.1.199 google.com

# 3. Cleanup
just test::destroy
```

### Production Environment (Initial Deployment)

```bash
# Full deployment (LXCs + Pi-hole + cloudflared + nebula-sync)
just prod::full

# Or step by step:
just prod::apply     # Create/update LXCs (Terraform)
just prod::deploy    # Install Pi-hole (Ansible)
just prod::dns       # Register DNS entries for Pi-holes
just prod::validate  # Test DNS on all 4 instances
```

### Blue-Green Deployment (Updates)

Deploy to one tier at a time to minimize DNS downtime:

```bash
# Deploy secondaries first (green)
just prod::deploy-green

# Verify secondaries
dig @192.168.1.21 google.com
dig @192.168.1.23 google.com

# Deploy primaries (blue)
just prod::deploy-blue

# Final verification
just prod::validate
```

**Deployment groups:**

| Group | Hosts | Includes |
| ------- | ------- | ---------- |
| green (secondary) | 21, 23 | pihole + cloudflared + nebula-sync |
| blue (primary) | 20, 22 | pihole + cloudflared (no nebula-sync) |

## What Terraform Does vs Ansible

**Terraform creates:**
- ✅ LXC containers on Proxmox
- ✅ Network interfaces (3 per LXC)
- ✅ SSH key injection
- ✅ Startup order configuration
- ✅ HA anti-affinity rules

**Ansible installs:**
- ✅ Pi-hole v6 (unattended)
- ✅ Admin password
- ✅ Web UI binding (mgmt + transfer networks)
- ✅ Cloudflared DoH proxy
- ✅ Pi-hole upstream to cloudflared
- ✅ nebula-sync on secondaries

## Upgrades (Blue-Green)

```bash
# Check current versions
just prod::upgrade-check

# Upgrade primaries first (blue)
just prod::upgrade-blue

# Verify primaries
dig @192.168.1.20 google.com
dig @192.168.1.22 google.com

# Upgrade secondaries (green)
just prod::upgrade-green

# Final verification
just prod::validate
```

## Common Operations

### Test DNS

```bash
# All production instances
just prod::validate

# Test local DNS records (A records and CNAMEs)
just prod::validate-local

# Or manually (query via trusted IPs)
for ip in 192.168.1.20 192.168.1.21 192.168.1.22 192.168.1.23; do
  echo "Testing $ip: $(dig @$ip google.com +short +time=2)"
done
```

### Test Ad Blocking

```bash
dig @dns-standard-primary.lan doubleclick.net  # Should return 0.0.0.0
```

### SSH to Instance

```bash
ssh root@dns-standard-primary.lan
# Or via mgmt IP directly
ssh root@192.168.5.20
```

### Check Pi-hole Status

```bash
ssh root@dns-standard-primary.lan "pihole status"
```

### Force nebula-sync

```bash
ssh root@dns-standard-secondary.lan "systemctl start nebula-sync.service"
```

## Troubleshooting

### Ansible can't find pihole_password

Ensure inventory symlinks exist:

```bash
ls -la ansible/inventory/
# Should show: group_vars -> ../group_vars
```

### LXC won't start

```bash
ssh root@joseph "pct start 1020"
ssh root@joseph "journalctl -u pve-container@1020 -n 50"
```

### DNS not responding

```bash
ssh root@dns-standard-primary.lan "ss -tlnp | grep :53"
ssh root@dns-standard-primary.lan "systemctl status pihole-FTL"
```

### macOS DNS cache stale after deployment

After blue-green deployment restarts FTL, macOS may cache failed DNS lookups.
Symptoms: `just` commands fail with "Connect Server unreachable" or SSH can't resolve `.lan` hostnames.

```bash
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

### Cloudflared issues

```bash
ssh root@dns-standard-primary.lan "systemctl status cloudflared"
ssh root@dns-standard-primary.lan "dig @127.0.0.1 -p 5053 google.com"
```

### Terraform can't find base infrastructure

If terraform fails with "hub_state_path not found":
1. Ensure jacaranda-infra hub repository is cloned as a sibling directory
2. Verify hub's infrastructure/terraform/terraform.tfstate exists
3. Check base-infra module's hub_state_path variable

### Submodule not initialized

```bash
git submodule update --init --recursive
```

## Integration with Hub

This repository is **independent** but integrates with jacaranda-infra hub for:

1. **Base Infrastructure (base-infra module):**
   - Source: `git::https://github.com/poindexter12/jacaranda-shared-libs.git//infrastructure/terraform/modules/base-infra?ref=v1.4.0`
   - Provides: Proxmox API config, VLAN definitions, SSH public key
   - Hub state path: `${path.module}/../../../../jacaranda-infra/infrastructure/terraform/terraform.tfstate`

2. **DNS Aggregation (hub reads this repo):**
   - Hub's infrastructure/dns/terraform/envs/prod/justfile scans this repository
   - Reads output `cname_entries` from terraform/envs/prod/main.tf
   - Aggregates CNAMEs into centralized DNS layer

3. **VMID Ranges (vmid-ranges module):**
   - Source: lib/infrastructure/terraform/modules/vmid-ranges
   - Validates VMIDs are in correct allocation range (1020-1023 are LXC range 1001-1254)

**Important:** DO NOT modify hub's DNS aggregation or base infrastructure from this repository. Coordinate changes through hub repository or shared-libs.

## Related Documentation

| Topic | Location |
| ------- | ---------- |
| Justfile patterns | lib/infrastructure/just/PATTERNS.md |
| Secrets management | lib/infrastructure/just/secrets.just |
| Base infrastructure module | lib/infrastructure/terraform/modules/base-infra/ |
| VMID allocation | lib/.claude/skills/vmid-allocation.md |
| Shared libraries | https://github.com/poindexter12/jacaranda-shared-libs |
| Hub repository | https://github.com/poindexter12/jacaranda-infra |

## Tool Versions

**Managed by mise (mise.toml):**
- just: 1.40.0
- opentofu: 1.8.8
- uv: 0.5.20
- pre-commit: 4.0.1

**Managed by uv (pyproject.toml):**
- Python: >=3.12,<3.13
- Ansible: >=2.17,<2.18
- jmespath: >=1.0.1

**Update tools:**

```bash
just upgrade    # Update mise tools
just sync       # Sync Python dependencies
```

## Git Workflow

**Branch:** main (default)
**Commits:** Conventional Commits format preferred
**State files:** terraform.tfstate committed to git (gitignored but force-added for operational continuity)

**Update submodule:**

```bash
cd lib
git fetch --tags
git checkout v1.4.1  # or latest version
cd ..
git add lib
git commit -m "chore: update shared-libs to v1.4.1"
```

## Key Decisions

1. **Custom LXC Module:** Pi-hole requires 3 NICs, SSH cert signing, and HA anti-affinity - features not in shared LXC module. Custom module is intentional and required.

2. **Base-Infra Module Pattern:** Replaced terraform_remote_state with base-infra module for cleaner abstraction and version pinning.

3. **State File Management:** Force-added terraform state files to git despite gitignore, ensuring operational continuity during extraction.

4. **Standalone Repository:** Extracted from monorepo to enable independent development, testing, and deployment cycles.

5. **Blue-Green Deployment:** HA pairs (primary/secondary) allow zero-downtime updates by deploying to secondaries first, verifying, then updating primaries.

## Operational Principles

1. **Test First:** Always validate changes in test environment before production
2. **Blue-Green Updates:** Deploy to secondaries first, verify, then primaries
3. **Secrets External:** Never commit secrets - use 1Password references
4. **Hub Coordination:** Base infrastructure and DNS aggregation managed by hub
5. **Custom Module Justified:** Pi-hole's 3-NIC + HA requirements necessitate custom module
