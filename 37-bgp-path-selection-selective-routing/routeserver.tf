# Gate 1 (deploy_route_server): Azure Route Server. Gate 3 (deploy_vpn_gateway) adds a VPN gateway to the same VNet.
# Route Server never carries data traffic. It only exchanges routes over BGP with the NVAs and programs them into the VNet.

resource "azurerm_public_ip" "rs" {
  count               = var.deploy_route_server ? 1 : 0
  name                = "${var.name_prefix}-rs-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_route_server" "rs" {
  count                            = var.deploy_route_server ? 1 : 0
  name                             = "${var.name_prefix}-rs"
  location                         = azurerm_resource_group.lab.location
  resource_group_name              = azurerm_resource_group.lab.name
  sku                              = "Standard"
  public_ip_address_id             = azurerm_public_ip.rs[0].id
  subnet_id                        = azurerm_subnet.route_server.id
  branch_to_branch_traffic_enabled = var.branch_to_branch
  tags                             = local.tags
}

# One BGP peering per NVA. The NVA must peer with both Route Server addresses (two instances).
resource "azurerm_route_server_bgp_connection" "nva_a" {
  count           = var.deploy_route_server && var.deploy_nvas ? 1 : 0
  name            = "nva-a"
  route_server_id = azurerm_route_server.rs[0].id
  peer_asn        = var.nva_a_asn
  peer_ip         = "10.37.1.4"
}

resource "azurerm_route_server_bgp_connection" "nva_b" {
  count           = var.deploy_route_server && var.deploy_nvas ? 1 : 0
  name            = "nva-b"
  route_server_id = azurerm_route_server.rs[0].id
  peer_asn        = var.nva_b_asn
  peer_ip         = "10.37.1.5"
}
