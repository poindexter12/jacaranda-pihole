# Pi-hole Service

## Quick Reference

**Purpose:** Pi-hole DNS with cloudflared DoH on Proxmox LXC containers
**Location:** `services/pihole/`
**Secrets:** `secrets/services/pihole/.secrets.local`

**Quick Commands:**

```bash
cd services/pihole
make help              # Show all commands
make secrets           # Set PIHOLE_PASSWORD (first time)
make test-full         # Create test LXC + deploy Pi-hole
make test-destroy      # Destroy test instance
make prod-validate     # Test production DNS
```

## Architecture

**4 Production LXCs, 2 profiles, HA pairs:**

| Hostname | VMID | Node | Profile | Role | DNS IP | Mgmt IP |
|----------|------|------|---------|------|--------|---------|
| pihole-standard-20 | 120 | joseph | standard | primary | 192.168.1.20 | 192.168.5.20 |
| pihole-standard-21 | 121 | maxwell | standard | secondary | 192.168.1.21 | 192.168.5.21 |
| pihole-restricted-22 | 122 | joseph | restricted | primary | 192.168.1.22 | 192.168.5.22 |
| pihole-restricted-23 | 123 | maxwell | restricted | secondary | 192.168.1.23 | 192.168.5.23 |

**Test Instance:**

| Hostname | VMID | Node | DNS IP | Mgmt IP |
|----------|------|------|--------|---------|
| pihole-test-99 | 199 | joseph | 192.168.1.99 | 192.168.5.99 |

**Network interfaces per LXC:**

| Interface | VLAN | Purpose |
|-----------|------|---------|
| eth0 | trusted (192.168.1.x) | DNS queries from clients |
| eth1 | mgmt (192.168.5.x) | SSH, Web UI |
| eth2 | storage (192.168.11.x) | nebula-sync replication |

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
│       ├── test/               # Test instance (VMID 199)
│       │   ├── main.tf
│       │   ├── backend.tf
│       │   └── Makefile
│       └── prod/               # Production (VMIDs 120-123)
│           ├── main.tf
│           ├── backend.tf
│           └── Makefile
└── ansible/
    ├── ansible.cfg
    ├── Makefile
    ├── requirements.yml
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

**Location:** `secrets/services/pihole/.secrets.local`

**Setup:**

```bash
cd secrets
make pihole-secrets      # Prompts for password
make pihole-secrets-show # Display current
make check               # Verify all secrets
```

**Or from service directory:**

```bash
cd services/pihole
make secrets
make show-secrets
```

## Deployment Workflow

### Test Environment

```bash
cd services/pihole

# 1. Set password (first time only)
make secrets

# 2. Create test LXC + deploy Pi-hole
make test-full

# 3. Verify DNS
dig @192.168.1.99 google.com

# 4. Cleanup
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
|-------|-------|----------|
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

# Or manually
for ip in 192.168.1.20 192.168.1.21 192.168.1.22 192.168.1.23; do
  echo "$ip: $(dig +short @$ip google.com)"
done
```

### Test Ad Blocking

```bash
dig @192.168.1.20 doubleclick.net  # Should return 0.0.0.0
```

### SSH to Instance

```bash
ssh -i ~/.ssh/jacaranda root@192.168.5.20
```

### Check Pi-hole Status

```bash
ssh root@192.168.5.20 "pihole status"
```

### Force nebula-sync

```bash
ssh root@192.168.5.21 "systemctl start nebula-sync.service"
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
ssh root@joseph "pct start 120"
ssh root@joseph "journalctl -u pve-container@120 -n 50"
```

### DNS not responding

```bash
ssh root@192.168.5.20 "ss -tlnp | grep :53"
ssh root@192.168.5.20 "systemctl status pihole-FTL"
```

### Cloudflared issues

```bash
ssh root@192.168.5.20 "systemctl status cloudflared"
ssh root@192.168.5.20 "dig @127.0.0.1 -p 5053 google.com"
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
|-------|----------|
| Secrets management | `secrets/Makefile` |
| Base infrastructure | `infrastructure/terraform/` |
| Project conventions | `CLAUDE.md` |
