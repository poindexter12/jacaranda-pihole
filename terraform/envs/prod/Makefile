# Pi-hole Production Environment
#
# 4 LXC instances with blue-green upgrade support.

.DEFAULT_GOAL := help

TF = ~/.asdf/shims/tofu
OP_VAULT = Homelab

# Encryption passphrase from 1Password
ENCRYPTION_PASSPHRASE = $$(op read 'op://$(OP_VAULT)/opentofu/password')
TF_FLAGS = -var="encryption_passphrase=$(ENCRYPTION_PASSPHRASE)"

# ============================================================================
# TARGETS
# ============================================================================

##@ OpenTofu

init: ## Initialize OpenTofu
	$(TF) init $(TF_FLAGS)

plan: init ## Plan changes
	@$(TF) plan $(TF_FLAGS)

apply: init ## Apply changes
	@$(TF) apply -auto-approve $(TF_FLAGS)

destroy: ## Destroy all (DANGEROUS - prompts first)
	@echo "WARNING: This will destroy ALL production Pi-hole instances!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read _
	$(TF) init $(TF_FLAGS)
	@$(TF) destroy -auto-approve $(TF_FLAGS)

output: ## Show OpenTofu outputs
	$(TF) output $(TF_FLAGS)

validate: init ## Validate configuration
	$(TF) validate

clean: ## Remove .terraform directory
	rm -rf .terraform .terraform.lock.hcl

##@ Testing

test-dns: ## Test DNS on all 4 instances
	@echo "=== DNS Resolution (all 4 instances) ==="
	@for ip in 192.168.1.20 192.168.1.21 192.168.1.22 192.168.1.23; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-dns-blue: ## Test primaries (.20, .22)
	@echo "=== DNS Resolution (BLUE/primaries) ==="
	@for ip in 192.168.1.20 192.168.1.22; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-dns-green: ## Test secondaries (.21, .23)
	@echo "=== DNS Resolution (GREEN/secondaries) ==="
	@for ip in 192.168.1.21 192.168.1.23; do \
		echo -n "$$ip: "; \
		dig @$$ip google.com +short | head -1 || echo "FAIL"; \
	done

test-dns-local: ## Test local DNS records (Pi-hole custom entries)
	@echo "=== Local DNS Records (via primary 192.168.1.20) ==="
	@echo "A records (.trusted network):"
	@for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do \
		result=$$(dig @192.168.1.20 $$host.trusted +short 2>/dev/null | head -1); \
		echo "  $$host.trusted: $${result:-FAIL}"; \
	done
	@echo ""
	@echo "A records (.mgmt network):"
	@for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do \
		result=$$(dig @192.168.1.20 $$host.mgmt +short 2>/dev/null | head -1); \
		echo "  $$host.mgmt: $${result:-FAIL}"; \
	done
	@echo ""
	@echo "CNAME records (naked hostname → .trusted):"
	@for host in dns-standard-primary dns-standard-secondary dns-restricted-primary dns-restricted-secondary; do \
		result=$$(dig @192.168.1.20 $$host +short 2>/dev/null | head -1); \
		echo "  $$host: $${result:-FAIL}"; \
	done

test-block: ## Test ad blocking
	@echo "=== Ad Blocking Test ==="
	@echo "Standard (should block ads):"
	@echo "  .20: $$(dig @192.168.1.20 doubleclick.net +short)"
	@echo "  .21: $$(dig @192.168.1.21 doubleclick.net +short)"
	@echo "Restricted (should block ads + adult):"
	@echo "  .22: $$(dig @192.168.1.22 doubleclick.net +short)"
	@echo "  .23: $$(dig @192.168.1.23 doubleclick.net +short)"

##@ Help

help: ## Show this help
	@echo "Pi-hole Production Environment"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; section=""} \
		/^##@/ { section=substr($$0, 5); next } \
		/^[a-zA-Z_-]+:.*?##/ { \
			if (section != "" && section != lastsection) { \
				printf "\n\033[1m%s\033[0m\n", section; \
				lastsection=section \
			} \
			printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 \
		}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Instances:"
	@echo "  dns-standard-primary    (10020) - 192.168.1.20  [workaround for template conflict]"
	@echo "  dns-standard-secondary  (1021)  - 192.168.1.21"
	@echo "  dns-restricted-primary  (1022)  - 192.168.1.22"
	@echo "  dns-restricted-secondary(1023)  - 192.168.1.23"
