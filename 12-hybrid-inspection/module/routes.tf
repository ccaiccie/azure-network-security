resource "azurerm_route_table" "gateway" {
  name                          = "gateway-to-spoke"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = true
  tags                          = local.tags
  route {
    name                   = "inspect-spoke"
    address_prefix         = "10.20.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  }
}
resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = azurerm_subnet.gateway["hub"].id
  route_table_id = azurerm_route_table.gateway.id
}
resource "azurerm_route_table" "branch" {
  name                          = "branch-safety"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = true
  tags                          = local.tags
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}
resource "azurerm_route_table" "spoke" {
  name                          = "spoke-return"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "inspect-branch-return"
    address_prefix         = "172.16.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  }
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}
resource "azurerm_subnet_route_table_association" "branch" {
  subnet_id      = azurerm_subnet.workload["branch"].id
  route_table_id = azurerm_route_table.branch.id
}
resource "azurerm_subnet_route_table_association" "spoke" {
  subnet_id      = azurerm_subnet.workload["spoke"].id
  route_table_id = azurerm_route_table.spoke.id
}
