# Pi-hole Production Environment
#
# 4 LXC instances with blue-green upgrade support.

.DEFAULT_GOAL := help

.PHONY: help init plan apply destroy output validate clean
.PHONY: test-dns test-dns-blue test-dns-green

TF = terraform

# Ansible configuration
ANSIBLE_DIR = ../../ansible
ANSIBLE_PLAYBOOK = ansible-playbook
ANSIBLE_OPTS = -i $(ANSIBLE_DIR)/inventory/prod.yml

# Secrets (centralized in secrets/services/pihole/)
SECRETS_DIR = ../../../../../secrets/services/pihole
SECRETS_FILE = $(SECRETS_DIR)/.secrets.local

# Note: Secrets are sourced at shell time in ansible/Makefile, not parsed as Make syntax
# This avoids corruption of passwords containing $ or # characters

# ============================================================================
# TERRAFORM
# ============================================================================

init:
	$(TF) init

plan: init
	$(TF) plan

apply: init
	$(TF) apply -auto-approve

destroy:
	@echo "WARNING: This will destroy ALL production Pi-hole instances!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read _
	$(TF) init
	$(TF) destroy -auto-approve

output:
	$(TF) output

validate: init
	$(TF) validate

clean:
	rm -rf .terraform .terraform.lock.hcl

# ============================================================================
# DNS TESTING
# ============================================================================

test-dns:
	@echo "=== DNS Resolution (all 4 instances) ==="
	@for ip in 192.168.1.20 192.168.1.21 192.168.1.22 192.168.1.23; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-dns-blue:
	@echo "=== DNS Resolution (BLUE/primaries) ==="
	@for ip in 192.168.1.20 192.168.1.22; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-dns-green:
	@echo "=== DNS Resolution (GREEN/secondaries) ==="
	@for ip in 192.168.1.21 192.168.1.23; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-block:
	@echo "=== Ad Blocking Test ==="
	@echo "Standard (should block ads):"
	@echo "  .20: $$(dig @192.168.1.20 doubleclick.net +short)"
	@echo "  .21: $$(dig @192.168.1.21 doubleclick.net +short)"
	@echo "Restricted (should block ads + adult):"
	@echo "  .22: $$(dig @192.168.1.22 doubleclick.net +short)"
	@echo "  .23: $$(dig @192.168.1.23 doubleclick.net +short)"

# ============================================================================
# SECRETS
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
	@echo "Pi-hole Production Environment"
	@echo ""
	@echo "Terraform:"
	@echo "  make init      - Initialize Terraform"
	@echo "  make plan      - Plan changes"
	@echo "  make apply     - Apply changes"
	@echo "  make destroy   - Destroy all (DANGEROUS)"
	@echo "  make output    - Show outputs"
	@echo ""
	@echo "Testing:"
	@echo "  make test-dns       - Test DNS on all 4 instances"
	@echo "  make test-dns-blue  - Test primaries (.20, .22)"
	@echo "  make test-dns-green - Test secondaries (.21, .23)"
	@echo "  make test-block     - Test ad blocking"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets         - Set password (prompts)"
	@echo "  make show-secrets    - Display current"
	@echo ""
	@echo "Instances:"
	@echo "  pihole-standard-20   (VMID 120) - primary"
	@echo "  pihole-standard-21   (VMID 121) - secondary"
	@echo "  pihole-restricted-22 (VMID 122) - primary"
	@echo "  pihole-restricted-23 (VMID 123) - secondary"
