output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "vnet_ids" {
  description = "IDs of the client and server VNets."
  value = {
    client = azurerm_virtual_network.client.id
    server = azurerm_virtual_network.server.id
  }
}

output "network_watcher" {
  description = "The regional Network Watcher the lab uses."
  value       = local.watcher_name
}

output "workspace_id" {
  description = "Workspace ID (GUID) for az monitor log-analytics query (empty without gate 2)."
  value       = try(azurerm_log_analytics_workspace.lab[0].workspace_id, "")
}

output "storage_account" {
  description = "Storage account for flow logs and packet captures (empty without gate 2)."
  value       = try(azurerm_storage_account.logs[0].name, "")
}

output "firewall_private_ip" {
  description = "Private IP of the firewall (empty without gate 5)."
  value       = try(azurerm_firewall.lab[0].ip_configuration[0].private_ip_address, "")
}
