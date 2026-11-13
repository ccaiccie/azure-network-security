# Free network objects: resource group, hub VNet, subnets and the route table used on the workload subnet.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-37-bgp-path-selection", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Hub VNet 10.37.0.0/16. Route Server needs a subnet named exactly RouteServerSubnet (a /27 or larger; check current docs).
resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.37.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "route_server" {
  name                 = "RouteServerSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.37.0.0/27"]
}

resource "azurerm_subnet" "nva" {
  name                 = "snet-nva"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.37.1.0/24"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.37.2.0/24"]
}

# Only used when gate 3 is open. The subnet itself is free.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.37.255.0/27"]
}

# Route table on snet-app. Activity 7 flips app_bgp_route_propagation and adds a None (blackhole) route.
resource "azurerm_route_table" "app" {
  name                          = "${var.name_prefix}-app-rt"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = var.app_bgp_route_propagation
  tags                          = local.tags

  dynamic "route" {
    for_each = var.blackhole_prefix == "" ? [] : [var.blackhole_prefix]
    content {
      name           = "blackhole"
      address_prefix = route.value
      next_hop_type  = "None"
    }
  }
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app.id
}
