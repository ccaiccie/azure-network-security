output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "vnet_name" {
  description = "Name of the lab VNet."
  value       = azurerm_virtual_network.lab.name
}

output "web_nic_name" {
  description = "Name of the web VM's NIC (empty when deploy_vms is false)."
  value       = try(azurerm_network_interface.web[0].name, "")
}

output "app_nic_name" {
  description = "Name of the app VM's NIC (empty when deploy_vms is false)."
  value       = try(azurerm_network_interface.app[0].name, "")
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint (empty when deploy_private_endpoint is false)."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, "")
}

output "flow_log_storage_account" {
  description = "Storage account that receives the flow log blobs (empty when enable_flow_logs is false)."
  value       = try(azurerm_storage_account.flow[0].name, "")
}
