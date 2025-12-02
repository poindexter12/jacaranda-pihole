# ============================================================================
# Production Environment Backend
# ============================================================================
# Local state - separate from test.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
