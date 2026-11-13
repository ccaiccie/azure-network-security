resource "azurerm_virtual_network" "a" {
  count               = local.on
  name                = "vnet-a"
  location            = azurerm_resource_group.lab[0].location
  resource_group_name = azurerm_resource_group.lab[0].name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "app" {
  count                           = local.on
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.lab[0].name
  virtual_network_name            = azurerm_virtual_network.a[0].name
  address_prefixes                = ["10.10.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "nva" {
  count                           = local.on
  name                            = "snet-nva"
  resource_group_name             = azurerm_resource_group.lab[0].name
  virtual_network_name            = azurerm_virtual_network.a[0].name
  address_prefixes                = ["10.10.2.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network" "b" {
  count               = local.on
  name                = "vnet-b"
  location            = azurerm_resource_group.lab[0].location
  resource_group_name = azurerm_resource_group.lab[0].name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "work" {
  count                           = local.on
  name                            = "snet-work"
  resource_group_name             = azurerm_resource_group.lab[0].name
  virtual_network_name            = azurerm_virtual_network.b[0].name
  address_prefixes                = ["10.20.1.0/24"]
  default_outbound_access_enabled = false
}

# Both directions are needed: a peering is two one-way resources.
resource "azurerm_virtual_network_peering" "a_to_b" {
  count                        = local.on
  name                         = "a-to-b"
  resource_group_name          = azurerm_resource_group.lab[0].name
  virtual_network_name         = azurerm_virtual_network.a[0].name
  remote_virtual_network_id    = azurerm_virtual_network.b[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "b_to_a" {
  count                        = local.on
  name                         = "b-to-a"
  resource_group_name          = azurerm_resource_group.lab[0].name
  virtual_network_name         = azurerm_virtual_network.b[0].name
  remote_virtual_network_id    = azurerm_virtual_network.a[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
