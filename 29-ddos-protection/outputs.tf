output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "vnet_name" {
  description = "Name of the lab VNet."
  value       = azurerm_virtual_network.lab.name
}

output "ddos_plan_id" {
  description = "ID of the DDoS protection plan (empty unless gate 3 is open with the acknowledgement)."
  value       = try(azurerm_network_ddos_protection_plan.lab[0].id, "")
}

output "public_ip_web" {
  description = "Address of pip-web, the protected public IP (empty without gate 1)."
  value       = try(azurerm_public_ip.web[0].ip_address, "")
}

output "public_ip_spare" {
  description = "Address of pip-spare, attached to nothing (empty without gate 1)."
  value       = try(azurerm_public_ip.spare[0].ip_address, "")
}

output "web_protection_mode" {
  description = "The protection mode set on pip-web. Coverage also depends on the VNet link and the attachment."
  value       = try(azurerm_public_ip.web[0].ddos_protection_mode, "")
}

output "workspace_name" {
  description = "Log Analytics workspace name (empty without gate 2)."
  value       = try(azurerm_log_analytics_workspace.lab[0].name, "")
}
