# Circuit resources. They bill from creation and carry nothing until a connectivity provider
# provisions them from the service key. Service key hand-over is out of band (see LAB-GUIDE).

resource "azurerm_express_route_circuit" "this" {
  for_each = local.circuits

  name                  = "${var.name_prefix}-circuit-${each.key}"
  location              = local.regions[each.key].location
  resource_group_name   = azurerm_resource_group.lab[0].name
  service_provider_name = each.value.service_provider_name
  peering_location      = each.value.peering_location
  bandwidth_in_mbps     = each.value.bandwidth_in_mbps
  tags                  = local.tags

  sku {
    tier   = var.circuit_sku_tier
    family = var.circuit_sku_family
  }
}

# Private peering. Only for circuits this module owns, and only after the provider has provisioned
# them. Some providers configure peering themselves: then leave this gate closed.
resource "azurerm_express_route_circuit_peering" "private" {
  for_each = var.configure_private_peering ? local.circuits : {}

  peering_type                  = "AzurePrivatePeering"
  express_route_circuit_name    = azurerm_express_route_circuit.this[each.key].name
  resource_group_name           = azurerm_resource_group.lab[0].name
  peer_asn                      = var.customer_asn
  primary_peer_address_prefix   = each.value.primary_peer_address_prefix
  secondary_peer_address_prefix = each.value.secondary_peer_address_prefix
  vlan_id                       = each.value.vlan_id
  shared_key                    = var.peering_shared_key
}
