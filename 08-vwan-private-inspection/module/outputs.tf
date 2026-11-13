output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "vwan_id" {
  value = azurerm_virtual_wan.lab.id
}
output "hub_id" {
  value = azurerm_virtual_hub.lab.id
}
output "hub_name" {
  value = azurerm_virtual_hub.lab.name
}
output "hub_default_route_table_id" {
  value = azurerm_virtual_hub.lab.default_route_table_id
}
output "firewall_id" {
  value = azurerm_firewall.lab.id
}
output "firewall_name" {
  value = azurerm_firewall.lab.name
}
output "firewall_private_ip" {
  value = one(azurerm_firewall.lab.virtual_hub).private_ip_address
}
output "firewall_public_ips" {
  value = one(azurerm_firewall.lab.virtual_hub).public_ip_addresses
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "routing_intent_id" {
  value = azurerm_virtual_hub_routing_intent.private.id
}
output "connection_ids" {
  value = { app = azurerm_virtual_hub_connection.app.id, backend = azurerm_virtual_hub_connection.backend.id }
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.vm["app"].id
}
output "backend_vm_id" {
  value = azurerm_linux_virtual_machine.vm["backend"].id
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.vm : k => v.id }
}
output "private_ips" {
  value = { app = local.app_ip, backend = local.backend_ip }
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
