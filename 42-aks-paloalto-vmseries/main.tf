# Free baseline: resource group, three VNets, subnets, four peerings, NSGs and two route tables with no routes.
# The user routes live in routes.tf because they need the firewalls.

locals {
  tags = merge({ lab = "cs42-aks-paloalto", managed_by = "terraform" }, var.tags)
  p    = var.name_prefix
}

resource "azurerm_resource_group" "lab" {
  name     = "${local.p}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- hub

resource "azurerm_virtual_network" "hub" {
  name                = "${local.p}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.70.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.70.0.0/24"]
}

resource "azurerm_subnet" "untrust" {
  name                 = "snet-untrust"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.70.1.0/24"]
}

resource "azurerm_subnet" "trust" {
  name                 = "snet-trust"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.70.2.0/24"]
}

# ---------------------------------------------------------------- spokes

resource "azurerm_virtual_network" "spoke_a" {
  name                = "${local.p}-spoke-a"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.71.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "aks_a" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke_a.name
  address_prefixes     = ["10.71.0.0/22"]
}

resource "azurerm_virtual_network" "spoke_b" {
  name                = "${local.p}-spoke-b"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.72.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "aks_b" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke_b.name
  address_prefixes     = ["10.72.0.0/22"]
}

# ---------------------------------------------------------------- peerings (forwarded traffic on both sides, no gateway)

resource "azurerm_virtual_network_peering" "a_to_hub" {
  name                         = "a-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_a.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_a" {
  name                         = "hub-to-a"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_a.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "b_to_hub" {
  name                         = "b-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_b.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_b" {
  name                         = "hub-to-b"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_b.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ---------------------------------------------------------------- NSGs

resource "azurerm_network_security_group" "mgmt" {
  name                = "${local.p}-nsg-mgmt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-mgmt-from-operator"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "22"]
    source_address_prefix      = var.mgmt_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "untrust" {
  name                = "${local.p}-nsg-untrust"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_network_security_group" "trust" {
  name                = "${local.p}-nsg-trust"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  # The probe comes from 168.63.129.16 (service tag AzureLoadBalancer). The default rules already allow it;
  # the explicit rule documents the dependency and survives a later deny rule.
  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "aks_a" {
  name                = "${local.p}-nsg-aks-a"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_network_security_group" "aks_b" {
  name                = "${local.p}-nsg-aks-b"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "untrust" {
  subnet_id                 = azurerm_subnet.untrust.id
  network_security_group_id = azurerm_network_security_group.untrust.id
}

resource "azurerm_subnet_network_security_group_association" "trust" {
  subnet_id                 = azurerm_subnet.trust.id
  network_security_group_id = azurerm_network_security_group.trust.id
}

resource "azurerm_subnet_network_security_group_association" "aks_a" {
  subnet_id                 = azurerm_subnet.aks_a.id
  network_security_group_id = azurerm_network_security_group.aks_a.id
}

resource "azurerm_subnet_network_security_group_association" "aks_b" {
  subnet_id                 = azurerm_subnet.aks_b.id
  network_security_group_id = azurerm_network_security_group.aks_b.id
}

# ---------------------------------------------------------------- route tables (routes are in routes.tf)

resource "azurerm_route_table" "a" {
  name                          = "${local.p}-rt-a"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags
}

resource "azurerm_route_table" "b" {
  name                          = "${local.p}-rt-b"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags
}

resource "azurerm_subnet_route_table_association" "a" {
  subnet_id      = azurerm_subnet.aks_a.id
  route_table_id = azurerm_route_table.a.id
}

resource "azurerm_subnet_route_table_association" "b" {
  subnet_id      = azurerm_subnet.aks_b.id
  route_table_id = azurerm_route_table.b.id
}
