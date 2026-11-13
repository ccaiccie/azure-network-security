# Free network objects: resource group, hub and spoke VNets with peering, and the node subnet's route table.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-38-container-security-inspection", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- hub VNet (firewall subnets)
resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

# The names AzureFirewallSubnet and AzureFirewallManagementSubnet are required by Azure.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.60.0.0/26"]
}

resource "azurerm_subnet" "firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.60.0.64/26"]
}

# ---------------------------------------------------------------- spoke VNet (cluster)
resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-spoke"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.61.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.node_subnet_cidr]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ---------------------------------------------------------------- route table on the node subnet
# Attached now, filled later: the default route needs the firewall's private IP, which Azure assigns
# when the firewall is created (firewall.tf). The cluster must be created with this table in place.
resource "azurerm_route_table" "nodes" {
  name                          = "${var.name_prefix}-nodes-rt"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags
}

resource "azurerm_subnet_route_table_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  route_table_id = azurerm_route_table.nodes.id
}
