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
  value = azurerm_linux_virtual_machine.app.id
}
output "app_nic_id" {
  value = azurerm_network_interface.app.id
}
output "app_private_ip" {
  value = local.app_ip
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "admin_username" {
  value = var.admin_username
}
output "origin_name" {
  value = azurerm_linux_web_app.origin.name
}
output "origin_id" {
  value = azurerm_linux_web_app.origin.id
}
output "origin_hostname" {
  value = azurerm_linux_web_app.origin.default_hostname
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "operator_cidr" {
  value = var.operator_cidr
}
output "image_version" {
  value = var.image_version
}
output "readiness_flags" {
  value = {
    deploy_lab                  = var.deploy_lab
    enable_tls_inspection       = var.enable_tls_inspection
    tls_prerequisites_confirmed = var.tls_prerequisites_confirmed
    origin_fixture_ready        = var.origin_fixture_ready
    application_rules_enabled   = local.rules_enabled
  }
}
