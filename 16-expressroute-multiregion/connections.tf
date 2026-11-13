# Four connections: each hub gateway to each circuit, with a weight.
# The weight steers Azure to on-premises when the same prefix arrives on several circuits.

resource "azurerm_virtual_network_gateway_connection" "er" {
  for_each = local.connections

  name                       = "hub${upper(each.value.hub)}-circ${upper(each.value.circuit)}"
  location                   = local.regions[each.value.hub].location
  resource_group_name        = azurerm_resource_group.lab[0].name
  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.er[each.value.hub].id
  express_route_circuit_id   = local.circuit_ids[each.value.circuit]
  routing_weight             = var.connection_weights[each.key]
  authorization_key          = lookup(var.authorization_keys, each.key, null)
  tags                       = local.tags
}
