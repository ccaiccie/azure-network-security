output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "location" {
  value = azurerm_resource_group.lab.location
}

output "firewall_name" {
  value = azurerm_firewall.egress.name
}

output "firewall_id" {
  value = azurerm_firewall.egress.id
}

output "firewall_private_ip" {
  description = "Actual computed IP. 10.10.0.4 in the diagrams is illustrative, not a configured allocation."
  value       = local.firewall_ip
}

output "firewall_public_ip" {
  description = "Expected public source of the baseline workload HTTPS flow. This is NOT the Bastion public IP."
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_policy_id" {
  value = azurerm_firewall_policy.egress.id
}

output "policy_mode" {
  value = var.policy_mode
}

output "allowed_fqdns" {
  value = local.allowed_fqdns
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.workload.name
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.workload.id
}

output "vm_private_ip" {
  value = azurerm_network_interface.workload.private_ip_address
}

output "nic_name" {
  value = azurerm_network_interface.workload.name
}

output "nic_id" {
  value = azurerm_network_interface.workload.id
}

output "route_table_id" {
  value = azurerm_route_table.spoke.id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.lab.name
}

output "workspace_id" {
  description = "Azure resource ID, NOT the customer GUID used by az monitor log-analytics query."
  value       = azurerm_log_analytics_workspace.lab.id
}

output "workspace_customer_id" {
  description = "Workspace/customer GUID for az monitor log-analytics query."
  value       = azurerm_log_analytics_workspace.lab.workspace_id
}

output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}

output "admin_username" {
  value = var.admin_username
}

output "bastion_ssh_command" {
  description = "Run on your workstation after replacing PRIVATE_KEY_PATH with an existing local private-key path."
  value       = "az network bastion ssh --resource-group ${azurerm_resource_group.lab.name} --name ${azurerm_bastion_host.lab.name} --target-resource-id ${azurerm_linux_virtual_machine.workload.id} --auth-type ssh-key --username ${var.admin_username} --ssh-key PRIVATE_KEY_PATH"
}
