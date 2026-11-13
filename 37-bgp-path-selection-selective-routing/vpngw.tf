# Gate 3 (deploy_vpn_gateway), optional: a BGP-enabled VPN gateway in the hub VNet.
# There is no simulated tunnel peer in this lab, so the gateway has no connection. It is here to show the interaction with
# Route Server (the branch_to_branch switch) and to practise the gateway's learned and advertised route commands.
# Billed by the hour and slow to create. Check provider docs for attribute names (bgp_enabled, bgp_settings).

resource "azurerm_public_ip" "gw" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "${var.name_prefix}-gw-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "${var.name_prefix}-vpngw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_sku
  generation          = "Generation1"
  bgp_enabled         = true
  tags                = local.tags

  ip_configuration {
    name                          = "gwip1"
    public_ip_address_id          = azurerm_public_ip.gw[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  bgp_settings {
    asn = var.azure_bgp_asn
  }
}
