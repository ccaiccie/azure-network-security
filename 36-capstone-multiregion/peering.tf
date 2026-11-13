# REFERENCE SKELETON: peering (gate 3). Spokes peer to their hub only; spokes never peer to each other.
# Hub to hub is global peering and is NOT transitive: that is why each firewall needs a route to the other one.

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = var.enable_peering ? local.spokes : {}
  name                         = "hub-to-${each.value.name}"
  resource_group_name          = azurerm_resource_group.region[each.value.region].name
  virtual_network_name         = azurerm_virtual_network.hub[each.value.region].name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.deploy_vpn_sim && each.value.region == "a"
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = var.enable_peering ? local.spokes : {}
  name                         = "${each.value.name}-to-hub"
  resource_group_name          = azurerm_resource_group.region[each.value.region].name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub[each.value.region].id
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.deploy_vpn_sim && each.value.region == "a"
  allow_virtual_network_access = true

  # The remote gateway must exist before a spoke may use it.
  depends_on = [azurerm_virtual_network_gateway.hub_a]
}

resource "azurerm_virtual_network_peering" "hub_a_to_b" {
  count                        = var.enable_peering && var.deploy_region_a && var.deploy_region_b ? 1 : 0
  name                         = "hub-a-to-hub-b"
  resource_group_name          = azurerm_resource_group.region["a"].name
  virtual_network_name         = azurerm_virtual_network.hub["a"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub["b"].id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "hub_b_to_a" {
  count                        = var.enable_peering && var.deploy_region_a && var.deploy_region_b ? 1 : 0
  name                         = "hub-b-to-hub-a"
  resource_group_name          = azurerm_resource_group.region["b"].name
  virtual_network_name         = azurerm_virtual_network.hub["b"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub["a"].id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}
