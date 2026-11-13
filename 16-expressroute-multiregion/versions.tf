terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 6.0"
    }
  }
}

# Designed, not tested: argument names follow azurerm 4.x as remembered.
# Check the provider documentation for the version you install.
provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}
