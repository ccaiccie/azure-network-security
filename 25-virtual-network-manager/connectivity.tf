# Gate 2 (deploy_connectivity): two connectivity configurations, both hub-and-spoke on the static group.
#   v1: spokes talk to the hub only (group connectivity None).
#   v2: same, with direct connectivity inside the group (DirectlyConnected): spoke-a reaches spoke-b without the hub.
# Which one is committed is decided in deploy.tf by var.active_connectivity. Deploying v1 again is the rollback.
# The hub is NOT a member of the group: it is named in the configuration.

locals {
  conn_on = var.deploy_avnm && var.deploy_connectivity
}

resource "azurerm_network_manager_connectivity_configuration" "v1" {
  count                           = local.conn_on ? 1 : 0
  name                            = "conn-hubspoke-v1"
  network_manager_id              = azurerm_network_manager.lab[0].id
  connectivity_topology           = "HubAndSpoke"
  delete_existing_peering_enabled = var.delete_existing_peering
  description                     = "Hub-and-spoke, spokes not directly connected"

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.spokes[0].id
    use_hub_gateway    = var.use_hub_gateway
  }

  hub {
    resource_id   = azurerm_virtual_network.hub.id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}

resource "azurerm_network_manager_connectivity_configuration" "v2" {
  count                           = local.conn_on ? 1 : 0
  name                            = "conn-hubspoke-v2-direct"
  network_manager_id              = azurerm_network_manager.lab[0].id
  connectivity_topology           = "HubAndSpoke"
  delete_existing_peering_enabled = var.delete_existing_peering
  description                     = "Hub-and-spoke with direct connectivity between spokes in the group"

  applies_to_group {
    group_connectivity = "DirectlyConnected"
    network_group_id   = azurerm_network_manager_network_group.spokes[0].id
    use_hub_gateway    = var.use_hub_gateway
  }

  hub {
    resource_id   = azurerm_virtual_network.hub.id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}
