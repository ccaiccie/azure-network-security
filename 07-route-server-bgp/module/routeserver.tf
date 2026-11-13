resource "azurerm_public_ip" "routeserver" {
  name                = "routeserver-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
resource "azurerm_route_server" "lab" {
  name                             = "routeserver"
  resource_group_name              = azurerm_resource_group.lab.name
  location                         = azurerm_resource_group.lab.location
  sku                              = "Standard"
  public_ip_address_id             = azurerm_public_ip.routeserver.id
  subnet_id                        = azurerm_subnet.routeserver.id
  branch_to_branch_traffic_enabled = false
  hub_routing_preference           = "ASPath"
  tags                             = local.tags
  lifecycle {
    postcondition {
      condition     = length(self.virtual_router_ips) == 2 && alltrue([for ip in self.virtual_router_ips : can(cidrnetmask("${ip}/32")) && can(regex("^10[.]0[.]1[.]([0-9]|[1-5][0-9]|6[0-3])$", ip))]) && self.virtual_router_asn != 65010
      error_message = "Require two actual IPv4 Route Server peers in the dedicated subnet and a different service ASN."
    }
  }
}
resource "azurerm_route_server_bgp_connection" "nva" {
  for_each        = local.nvas
  name            = "peer-${each.key}"
  route_server_id = azurerm_route_server.lab.id
  peer_asn        = 65010
  peer_ip         = azurerm_network_interface.vm[each.key].private_ip_address
  # NIC/IP inputs, not VM/custom_data, prevent a graph cycle.
}
