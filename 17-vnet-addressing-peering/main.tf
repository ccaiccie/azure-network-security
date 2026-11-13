locals {
  hub_space     = "10.0.0.0/16"
  spoke_a_space = "10.10.0.0/16"
  spoke_c_space = "10.30.0.0/16"

  # break_fix = overlap puts spoke-b inside the hub range, so peering them must fail.
  spoke_b_space  = var.break_fix == "overlap" ? "10.0.128.0/17" : "10.20.0.0/16"
  spoke_b_subnet = var.break_fix == "overlap" ? "10.0.130.0/24" : "10.20.1.0/24"
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ------------------------------------------------------------------ hub
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.hub_space]
  tags                = var.tags
}

resource "azurerm_subnet" "hub_shared" {
  name                            = "snet-shared"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = ["10.0.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "hub_nva" {
  name                            = "snet-nva"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
}

# The name GatewaySubnet is mandatory. /27 is the commonly recommended size.
resource "azurerm_subnet" "hub_gateway" {
  count                = var.create_gateway ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.254.0/27"]
}

# ------------------------------------------------------------------ spokes
resource "azurerm_virtual_network" "spoke_a" {
  name                = "vnet-spoke-a"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.spoke_a_space]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke_a_app" {
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke_a.name
  address_prefixes                = ["10.10.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network" "spoke_b" {
  name                = "vnet-spoke-b"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.spoke_b_space]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke_b_app" {
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke_b.name
  address_prefixes                = [local.spoke_b_subnet]
  default_outbound_access_enabled = false
}

# spoke-c lives in another region: peering it with the hub is GLOBAL peering.
resource "azurerm_virtual_network" "spoke_c" {
  count               = var.create_global_peering ? 1 : 0
  name                = "vnet-spoke-c"
  location            = var.secondary_location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.spoke_c_space]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke_c_app" {
  count                           = var.create_global_peering ? 1 : 0
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke_c[0].name
  address_prefixes                = ["10.30.1.0/24"]
  default_outbound_access_enabled = false
}
