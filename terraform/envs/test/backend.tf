# ============================================================================
# Test Environment Backend
# ============================================================================
# Local state - separate from production.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
