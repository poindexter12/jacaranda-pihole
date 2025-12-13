# OpenTofu State Encryption Configuration
# Copy this file to each terraform directory that needs state encryption
#
# Usage in Makefile:
#   TF_VAR_encryption_passphrase=$$(op read 'op://Homelab/opentofu/password') tofu plan
#
# Documentation: https://opentofu.org/docs/language/state/encryption/

terraform {
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    # Method for reading unencrypted state during migration
    method "unencrypted" "migrate" {}

    state {
      method   = method.aes_gcm.default
      enforced = false # Set to true after all state is encrypted

      # Fallback allows reading unencrypted state, writes encrypted
      fallback {
        method = method.unencrypted.migrate
      }
    }

    # Uncomment to also encrypt plan files:
    # plan {
    #   method   = method.aes_gcm.default
    #   enforced = false
    # }
  }
}

variable "encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for state encryption. Source: op://Homelab/opentofu/password"
}
