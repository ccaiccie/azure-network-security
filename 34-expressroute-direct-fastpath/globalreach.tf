# Gate 5: Global Reach between two circuits. Inputs are peering ids, because this lab creates at most one circuit.

resource "azurerm_express_route_circuit_connection" "gr" {
  count               = var.deploy_global_reach ? 1 : 0
  name                = "${var.name_prefix}-global-reach"
  peering_id          = var.global_reach_peering_id
  peer_peering_id     = var.global_reach_peer_peering_id
  address_prefix_ipv4 = var.global_reach_range

  lifecycle {
    precondition {
      condition     = var.global_reach_peering_id != "" && var.global_reach_peer_peering_id != ""
      error_message = "Gate 5 needs both private peering ids. Run scripts/er-tools.py overlap on the /29 first."
    }
  }
}
