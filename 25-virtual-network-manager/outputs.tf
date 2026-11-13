output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "network_manager_name" {
  description = "Name of the network manager (empty without gate 1)."
  value       = try(azurerm_network_manager.lab[0].name, "")
}

output "vnet_ids" {
  description = "IDs of the hub and the spoke VNets."
  value = {
    hub     = azurerm_virtual_network.hub.id
    spoke_a = azurerm_virtual_network.a.id
    spoke_b = azurerm_virtual_network.b.id
    spoke_c = azurerm_virtual_network.c.id
  }
}

output "static_group_id" {
  description = "ID of the static network group (empty without gate 1)."
  value       = try(azurerm_network_manager_network_group.spokes[0].id, "")
}

output "dynamic_group_id" {
  description = "ID of the dynamic network group (empty without gate 4)."
  value       = try(azurerm_network_manager_network_group.dynamic[0].id, "")
}

output "committed_connectivity" {
  description = "Which connectivity configuration is committed (empty without gate 2)."
  value       = local.conn_on ? var.active_connectivity : ""
}

output "deployed_regions" {
  description = "Regions the configurations are committed to."
  value       = var.deployment_regions
}
