output "resource_group_name" {
  value = azurerm_resource_group.lab.name
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
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "vm_ids" {
  value = { for key, vm in azurerm_linux_virtual_machine.vm : key => vm.id }
}
output "nic_ids" {
  value = { for key, nic in azurerm_network_interface.vm : key => nic.id }
}
output "vnet_ids" {
  value = { for key, vnet in azurerm_virtual_network.lab : key => vnet.id }
}
output "route_table_ids" {
  value = { app = azurerm_route_table.app.id, firewall = azurerm_route_table.firewall.id, perimeter = azurerm_route_table.perimeter.id }
}
output "bastion_id" {
  value = azurerm_bastion_host.lab.id
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "private_ips" {
  value = { app = local.app_ip, perimeter = local.perimeter_ip, origin = local.origin_ip }
}
output "public_ips" {
  value = { perimeter = azurerm_public_ip.endpoint["perimeter"].ip_address, origin = azurerm_public_ip.endpoint["origin"].ip_address }
}
output "public_ip_ids" {
  value = { perimeter = azurerm_public_ip.endpoint["perimeter"].id, origin = azurerm_public_ip.endpoint["origin"].id, firewall_management = azurerm_public_ip.firewall_management.id, bastion = azurerm_public_ip.bastion.id }
}
output "source_mode" {
  value = var.source_mode
}
output "perimeter_source_prefix" {
  value = local.source_prefix
}
output "gate_state" {
  value = { fixtures_ready = var.fixtures_ready, private_routes_verified = var.private_routes_verified, perimeter_ready = var.perimeter_ready, origin_access_enabled = var.origin_access_enabled, test_paths_enabled = var.test_paths_enabled, allow_test_flow = var.allow_test_flow }
}
output "runtime_configs" {
  value = local.runtime_configs
}
