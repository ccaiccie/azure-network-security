# Free baseline: a resource group and five small VNets. Nothing here bills by the hour.
# hub 10.70.0.0/24, spoke-a 10.71.0.0/24, spoke-b 10.72.0.0/24, spoke-c 10.73.0.0/24, spoke-d 10.74.0.0/24 (second region, gate 6).
# The env tag on each spoke is what the dynamic network group in dynamic.tf selects on.

locals {
  tags = merge({ lab = "azure-25-virtual-network-manager", purpose = "study" }, var.tags)
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
  address_space       = ["10.70.0.0/24"]
  tags                = merge(local.tags, { role = "hub" })
}

resource "azurerm_subnet" "hub" {
  name                 = "snet-hub"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.70.0.0/26"]
}

resource "azurerm_virtual_network" "a" {
  name                = "${var.name_prefix}-spoke-a"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.71.0.0/24"]
  tags                = merge(local.tags, { role = "spoke", env = "prod" })
}

resource "azurerm_subnet" "a" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.a.name
  address_prefixes     = ["10.71.0.0/26"]
}

resource "azurerm_virtual_network" "b" {
  name                = "${var.name_prefix}-spoke-b"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.72.0.0/24"]
  tags                = merge(local.tags, { role = "spoke", env = "prod" })
}

resource "azurerm_subnet" "b" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.b.name
  address_prefixes     = ["10.72.0.0/26"]
}

resource "azurerm_virtual_network" "c" {
  name                = "${var.name_prefix}-spoke-c"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.73.0.0/24"]
  tags                = merge(local.tags, { role = "spoke", env = var.spoke_c_env })
}

resource "azurerm_subnet" "c" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.c.name
  address_prefixes     = ["10.73.0.0/26"]
}

# Gate 6: a spoke in a second region, to show that a deployment is regional.
resource "azurerm_resource_group" "second" {
  count    = var.deploy_second_region ? 1 : 0
  name     = "${var.name_prefix}-rg-second"
  location = var.secondary_location
  tags     = local.tags
}

resource "azurerm_virtual_network" "d" {
  count               = var.deploy_second_region ? 1 : 0
  name                = "${var.name_prefix}-spoke-d"
  location            = azurerm_resource_group.second[0].location
  resource_group_name = azurerm_resource_group.second[0].name
  address_space       = ["10.74.0.0/24"]
  tags                = merge(local.tags, { role = "spoke", env = "prod" })
}

resource "azurerm_subnet" "d" {
  count                = var.deploy_second_region ? 1 : 0
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.second[0].name
  virtual_network_name = azurerm_virtual_network.d[0].name
  address_prefixes     = ["10.74.0.0/26"]
}
