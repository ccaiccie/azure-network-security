resource "azurerm_route_table" "app" {
  count                         = local.on
  name                          = "rt-app"
  location                      = azurerm_resource_group.lab[0].location
  resource_group_name           = azurerm_resource_group.lab[0].name
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled
}

resource "azurerm_route_table" "work" {
  count                         = local.on
  name                          = "rt-work"
  location                      = azurerm_resource_group.lab[0].location
  resource_group_name           = azurerm_resource_group.lab[0].name
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled
}

# Same prefix as the system peering route: the user route wins the tie.
resource "azurerm_route" "to_b_via_nva" {
  count                  = local.on == 1 && local.forward_route ? 1 : 0
  name                   = "to-b-via-nva"
  resource_group_name    = azurerm_resource_group.lab[0].name
  route_table_name       = azurerm_route_table.app[0].name
  address_prefix         = "10.20.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.nva_ip
}

# Longer than the /16 above: wins on prefix length, whatever its source.
resource "azurerm_route" "to_b_blackhole" {
  count               = local.on == 1 && var.enable_blackhole_route ? 1 : 0
  name                = "to-b-24-none"
  resource_group_name = azurerm_resource_group.lab[0].name
  route_table_name    = azurerm_route_table.app[0].name
  address_prefix      = "10.20.1.0/24"
  next_hop_type       = "None"
}

# Forced tunnelling: replaces the system default route on snet-app only.
resource "azurerm_route" "default_via_nva" {
  count                  = local.on == 1 && var.enable_default_route ? 1 : 0
  name                   = "default-via-nva"
  resource_group_name    = azurerm_resource_group.lab[0].name
  route_table_name       = azurerm_route_table.app[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.nva_ip
}

# A service tag in place of an address range. Check current docs for supported tags and next hop types.
resource "azurerm_route" "storage_direct" {
  count               = local.on == 1 && var.enable_service_tag_route ? 1 : 0
  name                = "storage-direct"
  resource_group_name = azurerm_resource_group.lab[0].name
  route_table_name    = azurerm_route_table.app[0].name
  address_prefix      = "Storage"
  next_hop_type       = "Internet"
}

# The reply direction: longer than the peering /16, so it wins on prefix length.
resource "azurerm_route" "to_a_via_nva" {
  count                  = local.on == 1 && local.return_route ? 1 : 0
  name                   = "to-a-via-nva"
  resource_group_name    = azurerm_resource_group.lab[0].name
  route_table_name       = azurerm_route_table.work[0].name
  address_prefix         = "10.10.1.0/24"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.nva_ip
}

# Never associate a table that points at the appliance with snet-nva.
resource "azurerm_subnet_route_table_association" "app" {
  count          = local.on == 1 && local.associate ? 1 : 0
  subnet_id      = azurerm_subnet.app[0].id
  route_table_id = azurerm_route_table.app[0].id
}

resource "azurerm_subnet_route_table_association" "work" {
  count          = local.on == 1 && local.associate ? 1 : 0
  subnet_id      = azurerm_subnet.work[0].id
  route_table_id = azurerm_route_table.work[0].id
}
