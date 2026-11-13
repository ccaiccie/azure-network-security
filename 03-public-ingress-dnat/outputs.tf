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
  description = "Computed frontend F for /0 next hop, not a promise of backend-visible instance I."
  value       = local.firewall_ip
}
output "firewall_public_ip" {
  description = "Actual public data-plane P; not Bastion's separate public IP."
  value       = azurerm_public_ip.firewall.ip_address
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "public_http_url" {
  description = "Plain HTTP only, even on 8443. Null when publish_dnat=false; not a successful-probe result."
  value       = var.publish_dnat ? "http://${azurerm_public_ip.firewall.ip_address}:8443" : null
}
output "allowed_client_cidr" {
  value = var.allowed_client_cidr
}
output "backend" {
  value = {
    vm_name        = azurerm_linux_virtual_machine.backend.name
    vm_id          = azurerm_linux_virtual_machine.backend.id
    nic_name       = azurerm_network_interface.backend.name
    nic_id         = azurerm_network_interface.backend.id
    private_ip     = azurerm_network_interface.backend.private_ip_address
    subnet_id      = azurerm_subnet.backend.id
    route_table_id = azurerm_route_table.backend.id
    listen_port    = 8080
  }
}
output "backend_vm_id" {
  value = azurerm_linux_virtual_machine.backend.id
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
  description = "Log Analytics customer GUID for queries, distinct from ARM workspace ID."
  value       = azurerm_log_analytics_workspace.lab.workspace_id
}
output "experiment_settings" {
  value = {
    publish_dnat           = var.publish_dnat
    enable_default_route   = var.enable_default_route
    return_route_blackhole = var.return_route_blackhole
  }
}
output "image_version" {
  value = var.image_version
}
