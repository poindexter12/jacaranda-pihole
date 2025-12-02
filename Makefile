# Pi-hole Service
#
# Orchestrates terraform (LXC creation) and ansible (Pi-hole deployment).
# Supports test → prod promotion workflow.

.DEFAULT_GOAL := help

.PHONY: help
.PHONY: test-init test-plan test-apply test-destroy test-deploy test-full
.PHONY: prod-init prod-plan prod-apply prod-destroy prod-deploy prod-full
.PHONY: prod-upgrade prod-upgrade-green prod-validate
.PHONY: promote

# ============================================================================
# TEST ENVIRONMENT
# ============================================================================

test-init:
	@$(MAKE) -C terraform/envs/test init

test-plan:
	@$(MAKE) -C terraform/envs/test plan

test-apply:
	@$(MAKE) -C terraform/envs/test apply

test-destroy:
	@$(MAKE) -C terraform/envs/test destroy

test-deploy:
	@$(MAKE) -C ansible test-deploy

test-full: test-apply
	@echo ""
	@echo "=== Waiting for LXC to boot (30s) ==="
	@sleep 30
	@$(MAKE) test-deploy

# ============================================================================
# PROD ENVIRONMENT
# ============================================================================

prod-init:
	@$(MAKE) -C terraform/envs/prod init

prod-plan:
	@$(MAKE) -C terraform/envs/prod plan

prod-apply:
	@$(MAKE) -C terraform/envs/prod apply

prod-destroy:
	@$(MAKE) -C terraform/envs/prod destroy

prod-deploy:
	@$(MAKE) -C ansible prod-deploy

prod-full: prod-apply
	@echo ""
	@echo "=== Waiting for LXCs to boot (30s) ==="
	@sleep 30
	@$(MAKE) prod-deploy

prod-validate:
	@$(MAKE) -C terraform/envs/prod test-dns

# ============================================================================
# UPGRADES
# ============================================================================

prod-upgrade:
	@$(MAKE) -C ansible prod-upgrade

prod-upgrade-green:
	@$(MAKE) -C ansible prod-upgrade-green

# ============================================================================
# SECRETS (centralized in secrets/services/pihole/)
# ============================================================================

SECRETS_DIR = ../../secrets/services/pihole
SECRETS_FILE = $(SECRETS_DIR)/.secrets.local

# Note: Special characters in passwords are handled safely - the secrets file
# is sourced at shell time in ansible/Makefile, not parsed as Makefile syntax

secrets:
	@mkdir -p $(SECRETS_DIR)
	@echo "Pi-hole password (used for web UI and API):"
	@read -s -p "PIHOLE_PASSWORD: " pass && echo "PIHOLE_PASSWORD='$$pass'" > $(SECRETS_FILE) && chmod 600 $(SECRETS_FILE) && echo "" && echo "Saved to $(SECRETS_FILE)"

show-secrets:
	@if [ -f $(SECRETS_FILE) ]; then cat $(SECRETS_FILE); else echo "No secrets file. Run: make secrets"; fi

# ============================================================================
# PROMOTION WORKFLOW
# ============================================================================

# Full promotion: test LXC → deploy Pi-hole → validate → prompt for prod
promote: test-full
	@echo ""
	@$(MAKE) -C terraform/envs/test test-dns
	@echo ""
	@echo "=== Test instance deployed and validated ==="
	@echo "Run 'make prod-full' to deploy to production"

# ============================================================================
# HELP
# ============================================================================

help:
	@echo "Pi-hole Service"
	@echo ""
	@echo "Test Environment:"
	@echo "  make test-apply     - Create test LXC (Terraform)"
	@echo "  make test-deploy    - Install Pi-hole (Ansible)"
	@echo "  make test-full      - Create LXC + install Pi-hole"
	@echo "  make test-destroy   - Destroy test LXC"
	@echo ""
	@echo "Production Environment:"
	@echo "  make prod-apply     - Create/update LXCs (Terraform)"
	@echo "  make prod-deploy    - Install Pi-hole (Ansible)"
	@echo "  make prod-full      - Create LXCs + install Pi-hole"
	@echo "  make prod-validate  - Run DNS tests"
	@echo "  make prod-destroy   - Destroy all (DANGEROUS)"
	@echo ""
	@echo "Upgrades:"
	@echo "  make prod-upgrade       - Upgrade primaries (blue)"
	@echo "  make prod-upgrade-green - Upgrade secondaries (green)"
	@echo ""
	@echo "Workflow:"
	@echo "  make promote        - Full test deployment + validation"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets            - Set PIHOLE_PASSWORD (prompts)"
	@echo "  make show-secrets       - Display current password"
	@echo ""
	@echo "Typical flow:"
	@echo "  1. make secrets         # Set password first"
	@echo "  2. make test-full       # Create test LXC + install Pi-hole"
	@echo "  3. make test-destroy    # Clean up test"
	@echo "  4. make prod-full       # Deploy to production"
