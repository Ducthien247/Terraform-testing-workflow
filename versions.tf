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
  features {}
  subscription_id = var.subscription_id
}
