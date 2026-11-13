# Free network objects: resource group, VNet and the three VM subnets.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-22-outbound-snat-natgw", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.50.0.0/16"]
  tags                = local.tags
}

# The three VM subnets carry the private subnet flag (default outbound access).
resource "azurerm_subnet" "nat" {
  name                            = "snet-nat"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.50.1.0/24"]
  default_outbound_access_enabled = var.default_outbound_access_enabled
}

resource "azurerm_subnet" "lb" {
  name                            = "snet-lb"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.50.2.0/24"]
  default_outbound_access_enabled = var.default_outbound_access_enabled
}

resource "azurerm_subnet" "fw" {
  name                            = "snet-fw"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.50.3.0/24"]
  default_outbound_access_enabled = var.default_outbound_access_enabled
}
