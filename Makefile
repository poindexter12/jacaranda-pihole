# Pi-hole Service
#
# Orchestrates terraform (LXC creation) and ansible (Pi-hole deployment).
# Supports test → prod promotion workflow.
#
# Self-documenting: run `make` or `make help` to see all targets

.DEFAULT_GOAL := help

# ============================================================================
# CONFIGURATION
# ============================================================================

# 1Password convention: op://Homelab/{service}-{env}/{field}
OP_VAULT = Homelab
SERVICE = pihole

# ============================================================================
# TARGETS
# ============================================================================

##@ Test Environment

test-init: ## Initialize Terraform for test
	@$(MAKE) -C terraform/envs/test init

test-plan: ## Show Terraform plan for test
	@$(MAKE) -C terraform/envs/test plan

test-apply: ## Create test LXC (Terraform)
	@$(MAKE) -C terraform/envs/test apply

test-destroy: ## Destroy test LXC
	@$(MAKE) -C terraform/envs/test destroy

test-deploy: ## Install Pi-hole on test (Ansible)
	@$(MAKE) -C ansible test-deploy

test-dns: ## Register DNS entries for test
	@$(MAKE) -C ansible test-dns

test-full: test-apply ## Create LXC + wait + deploy Pi-hole
	@echo ""
	@echo "=== Waiting for LXC to boot (30s) ==="
	@sleep 30
	@$(MAKE) test-deploy

##@ Production Environment

prod-init: ## Initialize Terraform for prod
	@$(MAKE) -C terraform/envs/prod init

prod-plan: ## Show Terraform plan for prod
	@$(MAKE) -C terraform/envs/prod plan

prod-apply: ## Create/update prod LXCs (Terraform)
	@$(MAKE) -C terraform/envs/prod apply

prod-destroy: ## Destroy all prod LXCs (DANGEROUS)
	@$(MAKE) -C terraform/envs/prod destroy

prod-deploy: ## Install Pi-hole on prod (Ansible)
	@$(MAKE) -C ansible prod-deploy

prod-dns: ## Register DNS entries for prod
	@$(MAKE) -C ansible prod-dns

prod-full: prod-apply ## Create LXCs + wait + deploy Pi-hole
	@echo ""
	@echo "=== Waiting for LXCs to boot (30s) ==="
	@sleep 30
	@$(MAKE) prod-deploy

prod-validate: ## Run DNS tests on prod
	@$(MAKE) -C terraform/envs/prod test-dns

prod-validate-local: ## Test local DNS records (Pi-hole custom entries)
	@$(MAKE) -C terraform/envs/prod test-dns-local

prod-sign-certs: ## Sign host certificates with production CA
	@$(MAKE) -C ansible prod-sign-certs

##@ Blue-Green Deployment

prod-deploy-green: ## Deploy to secondaries first (green)
	@$(MAKE) -C ansible prod-deploy-green

prod-deploy-blue: ## Deploy to primaries after verification (blue)
	@$(MAKE) -C ansible prod-deploy-blue

prod-destroy-green: ## Destroy secondaries only
	@echo "=== Destroying secondaries (green) ==="
	cd terraform/envs/prod && ~/.asdf/shims/tofu destroy -compact-warnings \
		-target='module.pihole.proxmox_lxc.pihole["dns-standard-secondary"]' \
		-target='module.pihole.proxmox_lxc.pihole["dns-restricted-secondary"]'

prod-destroy-blue: ## Destroy primaries only
	@echo "=== Destroying primaries (blue) ==="
	cd terraform/envs/prod && ~/.asdf/shims/tofu destroy -compact-warnings \
		-target='module.pihole.proxmox_lxc.pihole["dns-standard-primary"]' \
		-target='module.pihole.proxmox_lxc.pihole["dns-restricted-primary"]'

##@ Upgrades

prod-upgrade-blue: ## Upgrade primaries (blue) - step 1
	@$(MAKE) -C ansible prod-upgrade-blue

prod-upgrade-green: ## Upgrade secondaries (green) - step 2
	@$(MAKE) -C ansible prod-upgrade-green

##@ Secrets

check-secrets: ## Verify 1Password items exist
	@$(MAKE) -C ansible check-secrets

##@ Workflow

promote: test-full ## Full test deployment + validation
	@echo ""
	@$(MAKE) -C terraform/envs/test test-dns
	@echo ""
	@echo "=== Test instance deployed and validated ==="
	@echo "Run 'make prod-full' to deploy to production"

##@ Help

help: ## Show this help
	@echo "Pi-hole Service (DNS)"
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
	@echo ""
	@echo "Typical flow:"
	@echo "  1. make check-secrets   # Verify 1Password"
	@echo "  2. make test-full       # Create + deploy test"
	@echo "  3. make test-dns        # Register DNS"
	@echo "  4. make prod-full       # Deploy to production"
