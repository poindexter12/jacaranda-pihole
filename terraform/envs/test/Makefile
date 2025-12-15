# Pi-hole Test Environment
#
# Single test instance for validating changes before production.

.DEFAULT_GOAL := help

TF = ~/.asdf/shims/tofu

# Secrets from 1Password
OP_VAULT = Homelab
ENCRYPTION_PASSPHRASE = $$(op read 'op://$(OP_VAULT)/opentofu/password')
TF_FLAGS = -var="encryption_passphrase=$(ENCRYPTION_PASSPHRASE)"

# ============================================================================
# TARGETS
# ============================================================================

##@ OpenTofu

init: ## Initialize OpenTofu
	$(TF) init $(TF_FLAGS)

plan: init ## Plan changes
	$(TF) plan $(TF_FLAGS)

apply: init ## Create test instance
	$(TF) apply -auto-approve $(TF_FLAGS)

destroy: init ## Destroy test instance
	$(TF) destroy -auto-approve $(TF_FLAGS)

output: ## Show OpenTofu outputs
	$(TF) output $(TF_FLAGS)

validate: init ## Validate configuration
	$(TF) validate

clean: ## Remove .terraform directory
	rm -rf .terraform .terraform.lock.hcl

##@ Testing

test: test-ssh test-dns ## Run all tests

test-dns: ## Test DNS resolution
	@echo "=== DNS Resolution Test ==="
	@dig @192.168.1.199 google.com +short && echo "DNS: PASS" || echo "DNS: FAIL"

test-ssh: ## Test SSH connectivity
	@echo "=== SSH Test ==="
	@ssh -o ConnectTimeout=5 root@192.168.5.199 "hostname" && echo "SSH: PASS" || echo "SSH: FAIL"

##@ Help

help: ## Show this help
	@echo "Pi-hole Test Environment"
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
	@echo "Instance: dns-test (VMID 1199)"
	@echo "  DNS IP:  192.168.1.199"
	@echo "  Mgmt IP: 192.168.5.199"
