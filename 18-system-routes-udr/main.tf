provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  on = var.deploy_lab ? 1 : 0

  # Addresses (RFC 1918 examples)
  app_ip  = "10.10.1.10"
  nva_ip  = "10.10.2.10"
  work_ip = "10.20.1.20"

  # Fault handling: each fault changes exactly one thing.
  nva_forwarding = var.fault != "forwarding_off"
  associate      = var.fault != "missing_association"
  forward_route  = var.enable_udr_forward && var.fault != "return_only"
  return_route   = var.enable_return_route || var.fault == "return_only"
}

resource "azurerm_resource_group" "lab" {
  count    = local.on
  name     = var.resource_group_name
  location = var.location
}
