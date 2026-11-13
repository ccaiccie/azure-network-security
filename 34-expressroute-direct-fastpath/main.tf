# Free network objects: resource group, hub and spoke VNets, subnets and peering.
# Nothing in this file bills by the hour. Peered data is charged by volume.

locals {
  tags = merge({ lab = "azure-34-expressroute-direct-fastpath", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.80.0.0/16"]
  tags                = local.tags
}

# The subnet must be named GatewaySubnet. A /27 is the usual minimum; check current docs for coexistence with a VPN gateway.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.255.0/27"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.1.0/24"]
}

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-spoke"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.81.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "spoke" {
  name                 = "snet-spoke"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.81.1.0/24"]
}

# Gateway transit is switched on only when the gateway exists, because use_remote_gateways fails without one.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.deploy_er_gateway
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.deploy_er_gateway
  allow_virtual_network_access = true

  depends_on = [azurerm_virtual_network_gateway.er]
}
