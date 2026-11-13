resource "azurerm_subnet" "gateway" {
  for_each             = local.gateways
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab[each.key].name
  address_prefixes     = [each.value]
  # No NSG, customer VM, default route or overlapping control-prefix interception.
}
resource "azurerm_public_ip" "gateway" {
  for_each            = local.gateways
  name                = "${each.key}-vpn-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}
resource "azurerm_virtual_network_gateway" "lab" {
  for_each            = local.gateways
  name                = "${each.key}-vpn-gateway"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"
  active_active       = false
  bgp_enabled         = false
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    public_ip_address_id          = azurerm_public_ip.gateway[each.key].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[each.key].id
  }
}
resource "azurerm_virtual_network_gateway_connection" "lab" {
  for_each                        = var.create_connections ? { hub-to-branch = { source = "hub", target = "branch" }, branch-to-hub = { source = "branch", target = "hub" } } : {}
  name                            = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.lab[each.value.source].id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.lab[each.value.target].id
  shared_key                      = var.vpn_shared_key
  bgp_enabled                     = false
  routing_weight                  = 10
  tags                            = local.tags
  # No custom crypto, BGP, VPN NAT, FastPath, selectors or forced tunnel.
  # Do not generate/output PSK. Provider stores the supplied key in plans/state.
  depends_on = [azurerm_subnet_route_table_association.gateway, azurerm_virtual_network_peering.spoke_to_hub]
}
