locals {
  tags = merge(var.tags, { scenario = "15-layered-waf", purpose = "isolated-teaching-lab" })
}
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "gateway" {
  name                = "gateway"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}
resource "azurerm_subnet" "gateway" {
  name                 = "appgateway"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.gateway.name
  address_prefixes     = ["10.60.1.0/24"]
}
resource "azurerm_public_ip" "gateway" {
  name                = "gateway-public"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
