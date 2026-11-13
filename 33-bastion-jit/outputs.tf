output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "bastion_subnet_prefix" {
  description = "Prefix of AzureBastionSubnet."
  value       = local.bastion_subnet_prefix
}

output "vm_private_ip" {
  description = "Private IP of vm-app (empty without gate 1)."
  value       = try(azurerm_network_interface.app[0].private_ip_address, "")
}

output "vm_public_ip" {
  description = "Temporary public IP of vm-app (empty unless vm_public_ip is true)."
  value       = try(azurerm_public_ip.vm[0].ip_address, "")
}

output "bastion_id" {
  description = "ID of the Bastion host (empty unless gate 2 is open with the acknowledgement)."
  value       = try(azurerm_bastion_host.lab[0].id, "")
}

output "bastion_public_ip" {
  description = "Public IP of Bastion (empty without gate 2)."
  value       = try(azurerm_public_ip.bastion[0].ip_address, "")
}

output "workspace_name" {
  description = "Log Analytics workspace name (empty without gate 2)."
  value       = try(azurerm_log_analytics_workspace.lab[0].name, "")
}
