# Pi-hole Ansible
#
# Deploys Pi-hole, cloudflared, and nebula-sync to LXC containers.
# Mirrors terraform envs pattern: test vs prod via inventory selection.

.DEFAULT_GOAL := help

.PHONY: help deps test-deploy test-pihole test-cloudflared
.PHONY: prod-deploy prod-pihole prod-cloudflared prod-nebula-sync prod-upgrade
.PHONY: ping-test ping-prod

ANSIBLE_PLAYBOOK = ansible-playbook
ANSIBLE = ansible

# Secrets (centralized in secrets/services/pihole/)
SECRETS_DIR = ../../../secrets/services/pihole
SECRETS_FILE = $(SECRETS_DIR)/.secrets.local

# Source secrets at shell time (not Make parse time) to handle special characters
# Make's -include corrupts passwords containing $ or # characters
SOURCE_SECRETS = if [ -z "$$PIHOLE_PASSWORD" ] && [ -f "$(SECRETS_FILE)" ]; then . "$(SECRETS_FILE)" && export PIHOLE_PASSWORD; fi

# ============================================================================
# DEPENDENCIES
# ============================================================================

deps:
	ansible-galaxy install -r requirements.yml

# ============================================================================
# TEST ENVIRONMENT
# ============================================================================

ping-test:
	$(ANSIBLE) -i inventory/test.yml all -m ping

test-deploy: test-pihole test-cloudflared
	@echo "Test deployment complete"

test-pihole:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/test.yml playbooks/pihole-lxc.yml

test-cloudflared:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/test.yml playbooks/pihole-cloudflared.yml

# ============================================================================
# PROD ENVIRONMENT
# ============================================================================

ping-prod:
	$(ANSIBLE) -i inventory/prod.yml all -m ping

prod-deploy: prod-pihole prod-cloudflared prod-nebula-sync
	@echo "Production deployment complete"

prod-pihole:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-lxc.yml

prod-cloudflared:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-cloudflared.yml

prod-nebula-sync:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/nebula-sync.yml

# ============================================================================
# BLUE-GREEN DEPLOYMENT
# ============================================================================

prod-deploy-green:
	@echo "=== Deploying to secondaries (green) ==="
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-lxc.yml --limit pihole_secondary
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-cloudflared.yml --limit pihole_secondary
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/nebula-sync.yml --limit pihole_secondary

prod-deploy-blue:
	@echo "=== Deploying to primaries (blue) ==="
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-lxc.yml --limit pihole_primary
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-cloudflared.yml --limit pihole_primary

# ============================================================================
# UPGRADES (Blue-Green)
# ============================================================================

prod-upgrade:
	@echo "=== Blue-Green Upgrade ==="
	@echo "Step 1: Upgrade primaries (blue)"
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-upgrade.yml --limit pihole_primary
	@echo ""
	@echo "Verify primaries are working, then run: make prod-upgrade-green"

prod-upgrade-green:
	@echo "Step 2: Upgrade secondaries (green)"
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-upgrade.yml --limit pihole_secondary

prod-upgrade-check:
	@$(SOURCE_SECRETS); $(ANSIBLE_PLAYBOOK) -i inventory/prod.yml playbooks/pihole-upgrade.yml --tags check

# ============================================================================
# PASSWORD MANAGEMENT
# ============================================================================

secrets:
	@mkdir -p $(SECRETS_DIR)
	@echo "Pi-hole password (used for web UI and API):"
	@read -s -p "PIHOLE_PASSWORD: " pass && echo "PIHOLE_PASSWORD='$$pass'" > $(SECRETS_FILE) && chmod 600 $(SECRETS_FILE) && echo "" && echo "Saved to $(SECRETS_FILE)"

show-secrets:
	@if [ -f "$(SECRETS_FILE)" ]; then \
		cat $(SECRETS_FILE); \
	elif [ -n "$$PIHOLE_PASSWORD" ]; then \
		echo "PIHOLE_PASSWORD=$$PIHOLE_PASSWORD (from environment)"; \
	else \
		echo "No password configured. Run: make secrets"; \
	fi

# ============================================================================
# HELP
# ============================================================================

help:
	@echo "Pi-hole Ansible"
	@echo ""
	@echo "Test Environment:"
	@echo "  make ping-test        - Test connectivity"
	@echo "  make test-deploy      - Full deployment (pihole + cloudflared)"
	@echo "  make test-pihole      - Install Pi-hole only"
	@echo "  make test-cloudflared - Install cloudflared only"
	@echo ""
	@echo "Production Environment:"
	@echo "  make ping-prod        - Test connectivity"
	@echo "  make prod-deploy      - Full deployment (pihole + cloudflared + nebula-sync)"
	@echo "  make prod-pihole      - Install Pi-hole only"
	@echo "  make prod-cloudflared - Install cloudflared only"
	@echo "  make prod-nebula-sync - Install nebula-sync only"
	@echo ""
	@echo "Blue-Green Deployment:"
	@echo "  make prod-deploy-green - Deploy secondaries (21, 23) first"
	@echo "  make prod-deploy-blue  - Deploy primaries (20, 22) after verification"
	@echo ""
	@echo "Upgrades:"
	@echo "  make prod-upgrade-check - Check versions (no changes)"
	@echo "  make prod-upgrade       - Upgrade primaries (blue)"
	@echo "  make prod-upgrade-green - Upgrade secondaries (green)"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets          - Set password (prompts)"
	@echo "  make show-secrets     - Display current"
	@echo ""
	@echo "Other:"
	@echo "  make deps             - Install Ansible Galaxy requirements"
