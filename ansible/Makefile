# Pi-hole Ansible
#
# Deploys Pi-hole, cloudflared, and nebula-sync to LXC containers.
# Secrets loaded from 1Password via `op read`.
# Verbose logs written to logs/ directory.
#
# Self-documenting: run `make help` to see all targets

.DEFAULT_GOAL := help

# ============================================================================
# CONFIGURATION
# ============================================================================

LOG_DIR = logs
LOG_FILE = $(LOG_DIR)/ansible-$(shell date +%Y%m%d-%H%M%S).log
export ANSIBLE_LOG_PATH = $(LOG_FILE)

$(shell mkdir -p $(LOG_DIR))

ANSIBLE_PLAYBOOK = ansible-playbook
ANSIBLE = ansible

# 1Password convention: op://Homelab/{service}-{env}/{field}
OP_VAULT = Homelab
SERVICE = pihole

# ============================================================================
# INCLUDES
# ============================================================================

include ../../../infrastructure/ansible/fetch.mk

# ============================================================================
# TARGETS
# ============================================================================

##@ Test Environment

ping-test: ## Test connectivity to test hosts
	$(ANSIBLE) -i inventory/test.yaml all -m ping

test-deploy: fetch test-pihole test-cloudflared ## Full test deployment (pihole + cloudflared)
	@echo "Test deployment complete"

test-sign-certs: ## Sign host certificates for test (uses test CA)
	@$(MAKE) -C ../../../ansible sign-certs-test INVENTORY=$(CURDIR)/inventory/test.yaml

test-ssh-ca: test-sign-certs ## Configure SSH CA on test (sign + configure)
	@$(ANSIBLE_PLAYBOOK) -i inventory/test.yaml playbooks/ssh-ca.yaml

test-pihole: ## Install Pi-hole on test
	@$(ANSIBLE_PLAYBOOK) -i inventory/test.yaml playbooks/pihole-lxc.yml \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-test/webpassword')"

test-cloudflared: ## Install cloudflared on test
	@$(ANSIBLE_PLAYBOOK) -i inventory/test.yaml playbooks/pihole-cloudflared.yml

test-dns: ## Register DNS entries for test instances
	@$(ANSIBLE_PLAYBOOK) -i inventory/test.yaml playbooks/pihole-dns-self.yml

##@ Production Environment

ping-prod: ## Test connectivity to prod hosts
	$(ANSIBLE) -i inventory/prod.yaml all -m ping

prod-deploy: fetch prod-pihole prod-cloudflared prod-nebula-sync ## Full prod deployment
	@echo "Production deployment complete"

prod-sign-certs: ## Sign host certificates for prod
	@$(MAKE) -C ../../../ansible sign-certs INVENTORY=$(CURDIR)/inventory/prod.yaml

prod-ssh-ca: prod-sign-certs ## Configure SSH CA on prod (sign + configure)
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/ssh-ca.yaml

prod-pihole: ## Install Pi-hole on prod
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-lxc.yml \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"

prod-cloudflared: ## Install cloudflared on prod
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-cloudflared.yml

prod-nebula-sync: ## Install nebula-sync on prod secondaries
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/nebula-sync.yml \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"

prod-dns: ## Register DNS entries for prod instances
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-dns-self.yml

##@ Blue-Green Deployment

prod-deploy-green: fetch ## Deploy to secondaries first (green)
	@echo "=== Deploying to secondaries (green) ==="
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-lxc.yml --limit pihole_secondary \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-cloudflared.yml --limit pihole_secondary
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/nebula-sync.yml --limit pihole_secondary \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"

prod-deploy-blue: fetch ## Deploy to primaries after verification (blue)
	@echo "=== Deploying to primaries (blue) ==="
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-lxc.yml --limit pihole_primary \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-cloudflared.yml --limit pihole_primary

##@ Upgrades

prod-upgrade-blue: ## Upgrade primaries (blue) - step 1
	@echo "=== Blue-Green Upgrade ==="
	@echo "Step 1: Upgrade primaries (blue)"
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-upgrade.yml --limit pihole_primary \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"
	@echo ""
	@echo "Verify primaries are working, then run: make prod-upgrade-green"

prod-upgrade-green: ## Upgrade secondaries (green) - step 2
	@echo "Step 2: Upgrade secondaries (green)"
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-upgrade.yml --limit pihole_secondary \
		-e "pihole_password=$$(op read 'op://$(OP_VAULT)/$(SERVICE)-prod/webpassword')"

prod-upgrade-check: ## Check versions without changes
	@$(ANSIBLE_PLAYBOOK) -i inventory/prod.yaml playbooks/pihole-upgrade.yml --tags check

##@ Secrets

check-secrets: ## Verify 1Password items exist
	@echo "Checking 1Password items..."
	@echo "Test: op://$(OP_VAULT)/$(SERVICE)-test/webpassword"
	@op read "op://$(OP_VAULT)/$(SERVICE)-test/webpassword" > /dev/null && echo "  ✓ $(SERVICE)-test exists" || echo "  ✗ $(SERVICE)-test missing"
	@echo "Prod: op://$(OP_VAULT)/$(SERVICE)-prod/webpassword"
	@op read "op://$(OP_VAULT)/$(SERVICE)-prod/webpassword" > /dev/null && echo "  ✓ $(SERVICE)-prod exists" || echo "  ✗ $(SERVICE)-prod missing"

##@ Logs

logs: ## Show latest log file
	@ls -t $(LOG_DIR)/*.log 2>/dev/null | head -1 | xargs cat || echo "No logs found"

logs-tail: ## Tail latest log file
	@ls -t $(LOG_DIR)/*.log 2>/dev/null | head -1 | xargs tail -f || echo "No logs found"

logs-clean: ## Remove old log files
	@rm -f $(LOG_DIR)/*.log && echo "Logs cleaned"

##@ Other

deps: ## Install Ansible Galaxy requirements
	ansible-galaxy install -r requirements.yml

##@ Help

help: ## Show this help
	@echo "Pi-hole Ansible"
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
	@echo "Secrets: op://$(OP_VAULT)/$(SERVICE)-{test,prod}/webpassword"
