# Pi-hole Service (DNS)

## Quick Reference

**Purpose:** Pi-hole DNS with cloudflared DoH on Proxmox LXC containers
**Location:** `services/pihole/`
**Secrets:** 1Password `op://Homelab/pihole-{test,prod}/webpassword`

**Quick Commands:**

```bash
cd services/pihole
make help              # Show all commands
make test-full         # Create test LXC + deploy Pi-hole
make test-destroy      # Destroy test instance
make prod-validate     # Test production DNS
make prod-dns          # Register DNS entries for Pi-holes
```

## Architecture

**4 Production LXCs, 2 profiles, HA pairs:**

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
| `{hostname}` | CNAME → .trusted | `dns-standard-primary` → 192.168.1.20 |

**Test Instance:**

| Hostname | VMID | Node | Trusted IP | Mgmt IP |
| ---------- | ------ | ------ | ------------ | --------- |
| pihole-test | 1199 | joseph | 192.168.1.199 | 192.168.5.199 |

**Network interfaces per LXC (functional naming):**

| Interface | VLAN | Purpose |
| ----------- | ------ | --------- |
| eth0 | trusted (192.168.1.x) | DNS queries from clients |
| eth1 | mgmt (192.168.5.x) | SSH, Web UI |
| eth2 | transfer (192.168.11.x) | nebula-sync replication |

## Directory Structure

```text
services/pihole/
├── Makefile                    # Orchestrates terraform + ansible
├── .gitignore
├── terraform/
│   ├── main.tf                 # LXC module
│   ├── variables.tf
│   ├── outputs.tf
│   └── envs/
│       ├── test/               # Test instance (VMID 1199)
│       │   ├── main.tf
│       │   ├── backend.tf
│       │   └── Makefile
│       └── prod/               # Production (VMIDs 1020-1023)
│           ├── main.tf
│           ├── backend.tf
│           └── Makefile
└── ansible/
    ├── ansible.cfg
    ├── Makefile
    ├── requirements.yaml
    ├── inventory/
    │   ├── test.yml            # Test inventory
    │   ├── prod.yml            # Production inventory
    │   ├── group_vars -> ../group_vars
    │   └── host_vars -> ../host_vars
    ├── group_vars/
    │   ├── all.yml
    │   └── pihole_lxc.yml
    ├── host_vars/
    │   └── pihole-*.yml
    ├── playbooks/
    │   ├── pihole-lxc.yml      # Install Pi-hole
    │   ├── pihole-cloudflared.yml  # Install cloudflared + configure
    │   ├── nebula-sync.yml     # HA sync (secondaries only)
    │   └── pihole-upgrade.yml  # Blue-green upgrades
    ├── templates/
    └── files/
        └── docker-compose.yaml
```

## Secrets

**1Password:** `op://Homelab/pihole-{test,prod}/webpassword`

**Verify:**

```bash
op read 'op://Homelab/pihole-test/webpassword'   # Test password
op read 'op://Homelab/pihole-prod/webpassword'   # Prod password
```

## Deployment Workflow

### Test Environment

```bash
cd services/pihole

# 1. Create test LXC + deploy Pi-hole
make test-full

# 2. Verify DNS
dig @192.168.1.99 google.com

# 3. Cleanup
make test-destroy
```

### Production Environment

```bash
cd services/pihole

# Full deployment (LXCs + Pi-hole + cloudflared + nebula-sync)
make prod-full

# Or step by step:
make prod-apply     # Create/update LXCs (Terraform)
make prod-deploy    # Install Pi-hole (Ansible)
make prod-dns       # Register DNS entries for Pi-holes
make prod-validate  # Test DNS on all 4 instances
```

### Blue-Green Deployment

Deploy to one tier at a time to minimize DNS downtime:

```bash
cd services/pihole/ansible

# Deploy secondaries first (green)
make prod-deploy-green

# Verify secondaries
dig @192.168.1.21 google.com
dig @192.168.1.23 google.com

# Deploy primaries (blue)
make prod-deploy-blue

# Final verification
make prod-validate
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

**Ansible installs:**

- ✅ Pi-hole v6 (unattended)
- ✅ Admin password
- ✅ Web UI binding (mgmt + transfer networks)
- ✅ Cloudflared DoH proxy
- ✅ Pi-hole upstream to cloudflared
- ✅ nebula-sync on secondaries

## Upgrades (Blue-Green)

```bash
cd services/pihole

# Check current versions
make -C ansible prod-upgrade-check

# Upgrade primaries first (blue)
make prod-upgrade

# Verify primaries
dig @192.168.1.20 google.com
dig @192.168.1.22 google.com

# Upgrade secondaries (green)
make prod-upgrade-green

# Final verification
make prod-validate
```

## Common Operations

### Test DNS

```bash
# All production instances
make prod-validate

# Or manually (uses DNS names)
for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do
  echo "$host: $(dig +short @$host.trusted google.com)"
done
```

### Test Ad Blocking

```bash
dig @dns-standard-primary.trusted doubleclick.net  # Should return 0.0.0.0
```

### SSH to Instance

```bash
ssh root@dns-standard-primary.mgmt
# Or short form (CNAME → trusted network, but SSH via mgmt)
ssh root@192.168.5.20
```

### Check Pi-hole Status

```bash
ssh root@dns-standard-primary.mgmt "pihole status"
```

### Force nebula-sync

```bash
ssh root@dns-standard-secondary.mgmt "systemctl start nebula-sync.service"
```

## Troubleshooting

### Ansible can't find pihole_password

Ensure inventory symlinks exist:

```bash
ls -la services/pihole/ansible/inventory/
# Should show: group_vars -> ../group_vars
```

### LXC won't start

```bash
ssh root@joseph "pct start 1020"
ssh root@joseph "journalctl -u pve-container@1020 -n 50"
```

### DNS not responding

```bash
ssh root@dns-standard-primary.mgmt "ss -tlnp | grep :53"
ssh root@dns-standard-primary.mgmt "systemctl status pihole-FTL"
```

### Cloudflared issues

```bash
ssh root@dns-standard-primary.mgmt "systemctl status cloudflared"
ssh root@dns-standard-primary.mgmt "dig @127.0.0.1 -p 5053 google.com"
```

## DO vs DON'T

### DO

- ✅ Run `make secrets` before first deployment
- ✅ Use test environment to validate changes
- ✅ Use blue-green upgrades for production
- ✅ Access web UI via mgmt network (192.168.5.x)
- ✅ Query DNS via trusted network (192.168.1.x)

### DON'T

- ❌ Modify LXC config in Proxmox UI (Terraform-managed)
- ❌ Install Pi-hole manually (use Ansible)
- ❌ Commit secrets to git
- ❌ Run nebula-sync on primary instances
- ❌ Skip the test environment for significant changes

## Related Documentation

| Topic | Location |
| ------- | ---------- |
| Makefile standards | `.claude/directives/makefile-conventions.md` |
| Services pattern | `services/CLAUDE.md` |
| Secrets management | `secrets/Makefile` |
| Base infrastructure | `infrastructure/terraform/` |
| Project conventions | `CLAUDE.md` |
