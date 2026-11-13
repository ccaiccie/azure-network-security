# Free network objects: resource group, the Azure-side VNet and its subnets.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-26-vpn-s2s-p2s", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Azure side: 10.60.0.0/16 with a GatewaySubnet and one workload subnet.
resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

# The subnet must be named GatewaySubnet. A /27 is the usual minimum; check current docs for larger designs.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.60.255.0/27"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.60.1.0/24"]
}
