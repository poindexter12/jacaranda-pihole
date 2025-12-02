# Pi-hole Test Environment
#
# Single test instance for validating changes before production.

.DEFAULT_GOAL := help

.PHONY: help init plan apply destroy output validate clean

TF = terraform

# ============================================================================
# TERRAFORM
# ============================================================================

init:
	$(TF) init

plan: init
	$(TF) plan

apply: init
	$(TF) apply -auto-approve

destroy: init
	$(TF) destroy -auto-approve

output:
	$(TF) output

validate: init
	$(TF) validate

clean:
	rm -rf .terraform .terraform.lock.hcl

# ============================================================================
# TESTING
# ============================================================================

test-dns:
	@echo "=== DNS Resolution Test ==="
	@dig @192.168.1.99 google.com +short && echo "DNS: PASS" || echo "DNS: FAIL"

test-ssh:
	@echo "=== SSH Test ==="
	@ssh -o ConnectTimeout=5 root@192.168.5.99 "hostname" && echo "SSH: PASS" || echo "SSH: FAIL"

test: test-ssh test-dns

# ============================================================================
# HELP
# ============================================================================

help:
	@echo "Pi-hole Test Environment"
	@echo ""
	@echo "Terraform:"
	@echo "  make init      - Initialize Terraform"
	@echo "  make plan      - Plan changes"
	@echo "  make apply     - Create test instance"
	@echo "  make destroy   - Destroy test instance"
	@echo "  make output    - Show outputs"
	@echo ""
	@echo "Testing:"
	@echo "  make test      - Run all tests"
	@echo "  make test-dns  - Test DNS resolution"
	@echo "  make test-ssh  - Test SSH connectivity"
	@echo ""
	@echo "Instance: pihole-test-99 (VMID 199)"
	@echo "  DNS IP:  192.168.1.99"
	@echo "  Mgmt IP: 192.168.5.99"
