terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Remote state in Azure Blob Storage. Uses partial configuration: the
  # storage account details are supplied at `terraform init` time via
  # -backend-config flags (see the GitHub Actions workflows) so no
  # environment-specific values are committed to the repo.
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # The old VM template's vault is being destroyed. Soft-delete it rather
      # than purging: purging needs an extra permission the CI principal may
      # not hold, and a failed purge fails the whole apply. Drop this block
      # once the vault is out of state.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
  }
  subscription_id = var.subscription_id
}
