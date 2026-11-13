resource "azurerm_route_table" "app" {
  name                          = "app-forced-default"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  }
}
resource "azurerm_route_table" "firewall" {
  name                          = "firewall-to-perimeter"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "default-to-perimeter"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.perimeter_ip
  }
}
resource "azurerm_route_table" "perimeter" {
  name                          = "perimeter-return"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "app-return-through-firewall"
    address_prefix         = "10.20.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  }
  # Keep system Internet default for exact guest-SNAT egress. No overlay default/loop.
}
resource "azurerm_subnet_route_table_association" "workload" {
  for_each       = { app = azurerm_route_table.app.id, perimeter = azurerm_route_table.perimeter.id }
  subnet_id      = azurerm_subnet.workload[each.key].id
  route_table_id = each.value
}
resource "azurerm_subnet_route_table_association" "firewall" {
  subnet_id      = azurerm_subnet.firewall.id
  route_table_id = azurerm_route_table.firewall.id
}
