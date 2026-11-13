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
  value = local.firewall_ip
}
output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.workload["app"].id
}
output "backend_vm_id" {
  value = azurerm_linux_virtual_machine.workload["backend"].id
}
output "app_nic_id" {
  value = azurerm_network_interface.workload["app"].id
}
output "backend_nic_id" {
  value = azurerm_network_interface.workload["backend"].id
}
output "app_private_ip" {
  value = local.app_ip
}
output "backend_private_ip" {
  value = local.backend_ip
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "admin_username" {
  value = var.admin_username
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "private_dns_zone" {
  value = azurerm_private_dns_zone.lab.name
}
output "allowed_host" {
  value = "allowed.policy.test"
}
output "denied_host" {
  value = "denied.policy.test"
}
output "policy_mode" {
  value = var.policy_mode
}
output "fixtures_ready" {
  value = var.fixtures_ready
}
output "experiments_confirmed" {
  value = var.experiments_confirmed
}
output "image_version" {
  value = var.image_version
}
