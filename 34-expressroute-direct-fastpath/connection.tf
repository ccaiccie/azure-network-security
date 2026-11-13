# Gate 3: connect the gateway to a circuit. FastPath is the express_route_gateway_bypass setting.
# The connection fails until the provider state of the circuit is Provisioned.

resource "azurerm_virtual_network_gateway_connection" "er" {
  count                        = var.deploy_connection && var.deploy_er_gateway ? 1 : 0
  name                         = "${var.name_prefix}-er-conn"
  location                     = azurerm_resource_group.lab.location
  resource_group_name          = azurerm_resource_group.lab.name
  type                         = "ExpressRoute"
  virtual_network_gateway_id   = azurerm_virtual_network_gateway.er[0].id
  express_route_circuit_id     = local.circuit_id
  express_route_gateway_bypass = var.enable_fastpath
  tags                         = local.tags

  lifecycle {
    precondition {
      condition     = local.circuit_id != "" && var.circuit_provisioned_confirmed
      error_message = "Gate 3 needs a circuit id (gate 2, gate 4 or existing_circuit_id) and circuit_provisioned_confirmed = true."
    }
  }
}
