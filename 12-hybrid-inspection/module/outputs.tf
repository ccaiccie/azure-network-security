output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "firewall_id" {
  value = azurerm_firewall.lab.id
}
output "firewall_name" {
  value = azurerm_firewall.lab.name
}
output "firewall_private_ip" {
  value = azurerm_firewall.lab.ip_configuration[0].private_ip_address
}
output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "vnet_ids" {
  value = { for k, v in azurerm_virtual_network.lab : k => v.id }
}
output "gateway_ids" {
  value = { for k, v in azurerm_virtual_network_gateway.lab : k => v.id }
}
output "gateway_public_ips" {
  value = { for k, v in azurerm_public_ip.gateway : k => v.ip_address }
}
output "gateway_public_ip_ids" {
  value = { for k, v in azurerm_public_ip.gateway : k => v.id }
}
output "connection_ids" {
  value = { for k, v in azurerm_virtual_network_gateway_connection.lab : k => v.id }
}
output "vm_ids" {
  value = { for k, v in azurerm_linux_virtual_machine.vm : k => v.id }
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.vm : k => v.id }
}
output "private_ips" {
  value = { branch = local.branch_ip, spoke = local.spoke_ip }
}
output "route_table_ids" {
  value = { gateway = azurerm_route_table.gateway.id, branch = azurerm_route_table.branch.id, spoke = azurerm_route_table.spoke.id }
}
output "bastion_ids" {
  value = { for k, v in azurerm_bastion_host.lab : k => v.id }
}
output "bastion_names" {
  value = { for k, v in azurerm_bastion_host.lab : k => v.name }
}
output "admin_username" {
  value = var.admin_username
}
output "image_id" {
  value = var.image_id
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "test_firewall_action" {
  value = local.test_firewall_action
}
output "test_nsg_action" {
  value = local.test_nsg_action
}
output "connections_enabled" {
  value = var.create_connections
}
