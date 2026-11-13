resource "azurerm_route_table" "client" {
  name                          = "client-pe-inspection"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name           = "other-egress-denied"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
  dynamic "route" {
    for_each = var.install_pe_host_route ? [1] : []
    content {
      name                   = "exact-pe-through-firewall"
      address_prefix         = "${local.endpoint_ip}/32"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
    }
  }
}
resource "azurerm_subnet_route_table_association" "client" {
  subnet_id      = azurerm_subnet.client.id
  route_table_id = azurerm_route_table.client.id
}
# No copied E/32 route on FirewallSubnet: its onward endpoint path must not recurse.
# No guest route table is invented for the PE managed NIC.
