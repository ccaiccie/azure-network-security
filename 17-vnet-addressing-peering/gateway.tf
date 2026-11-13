# COSTLY and slow: everything here is behind gates that default to false.
resource "azurerm_public_ip" "gateway" {
  count               = var.create_gateway ? 1 : 0
  name                = "pip-hub-vpngw"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "hub" {
  count               = var.create_gateway ? 1 : 0
  name                = "vpngw-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"
  active_active       = false
  bgp_enabled         = false
  tags                = var.tags

  ip_configuration {
    name                          = "gw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.hub_gateway[0].id
  }
}

# A pretend on-premises site. 203.0.113.10 and 192.168.100.0/24 are documentation-style examples.
resource "azurerm_local_network_gateway" "onprem" {
  count               = var.create_onprem_connection ? 1 : 0
  name                = "lng-onprem"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  gateway_address     = "203.0.113.10"
  address_space       = ["192.168.100.0/24"]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "onprem" {
  count                      = var.create_onprem_connection ? 1 : 0
  name                       = "cn-hub-to-onprem"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.lab.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.hub[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem[0].id
  shared_key                 = var.vpn_shared_key
  tags                       = var.tags

  lifecycle {
    precondition {
      condition     = var.vpn_shared_key != null
      error_message = "create_onprem_connection needs vpn_shared_key (set TF_VAR_vpn_shared_key; never put it in a file)."
    }
  }
}
