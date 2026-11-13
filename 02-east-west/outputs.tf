output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "firewall_name" {
  value = azurerm_firewall.lab.name
}
output "firewall_id" {
  value = azurerm_firewall.lab.id
}
output "firewall_private_ip" {
  description = "Computed F; never assume illustrative 10.0.1.4."
  value       = local.firewall_ip
}
output "firewall_public_ip" {
  description = "Firewall service public IP; NOT part of the private A-to-B flow."
  value       = azurerm_public_ip.firewall.ip_address
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "workloads" {
  value = {
    for role, config in local.workloads : role => {
      vm_name        = azurerm_linux_virtual_machine.workload[role].name
      vm_id          = azurerm_linux_virtual_machine.workload[role].id
      nic_name       = azurerm_network_interface.workload[role].name
      nic_id         = azurerm_network_interface.workload[role].id
      private_ip     = azurerm_network_interface.workload[role].private_ip_address
      route_table_id = azurerm_route_table.workload[role].id
      listen_ports   = config.listen_ports
      vnet_name      = config.vnet_key
      subnet_name    = config.subnet_name
    }
  }
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.workload["app"].id
}
output "db_vm_id" {
  value = azurerm_linux_virtual_machine.workload["db"].id
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
  description = "Customer GUID for Log Analytics CLI queries, not the ARM resource ID."
  value       = azurerm_log_analytics_workspace.lab.workspace_id
}
output "experiment_settings" {
  description = "Two-spoke baseline: explicit_remote_routes=true, return_route_blackhole=false, enable_same_vnet=false, same_vnet_return_route_enabled=true."
  value = {
    explicit_remote_routes         = var.explicit_remote_routes
    return_route_blackhole         = var.return_route_blackhole
    enable_same_vnet               = var.enable_same_vnet
    same_vnet_return_route_enabled = var.same_vnet_return_route_enabled
  }
}
output "image_version" {
  value = var.image_version
}

output "c_vm_id" {
  description = "Optional same-VNet endpoint; null when enable_same_vnet=false."
  value       = try(azurerm_linux_virtual_machine.workload["c"].id, null)
}
