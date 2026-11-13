output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "firewall_id" {
  value = azurerm_firewall.lab.id
}
output "firewall_name" {
  value = azurerm_firewall.lab.name
}
output "firewall_policy_id" {
  value = azurerm_firewall_policy.lab.id
}
output "firewall_private_ip" {
  value = azurerm_firewall.lab.ip_configuration[0].private_ip_address
}
output "bastion_id" {
  value = azurerm_bastion_host.lab.id
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "vm_ids" {
  value = { for k, v in azurerm_linux_virtual_machine.client : k => v.id }
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.client : k => v.id }
}
output "vnet_ids" {
  value = { for k, v in azurerm_virtual_network.lab : k => v.id }
}
output "private_ips" {
  value = local.clients
}
output "endpoint_ip" {
  value = local.endpoint_ip
}
output "endpoint_id" {
  value = azurerm_private_endpoint.blob.id
}
output "endpoint_subnet_id" {
  value = azurerm_subnet.endpoint.id
}
output "endpoint_nsg_id" {
  value = azurerm_network_security_group.endpoint.id
}
output "route_table_id" {
  value = azurerm_route_table.client.id
}
output "storage_account_id" {
  value = azurerm_storage_account.lab.id
}
output "storage_account_name" {
  value = azurerm_storage_account.lab.name
}
output "container_id" {
  value = azurerm_storage_container.lab.id
}
output "container_name" {
  value = local.container_name
}
output "blob_name" {
  value = local.blob_name
}
output "blob_fqdn" {
  value = local.blob_fqdn
}
output "blob_url" {
  value = "https://${local.blob_fqdn}/${local.container_name}/${local.blob_name}"
}
output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.blob.id
}
output "identity_principal_ids" {
  value = { for k, v in azurerm_linux_virtual_machine.client : k => v.identity[0].principal_id }
}
output "role_assignment_ids" {
  value = { for k, v in azurerm_role_assignment.blob : k => v.id }
}
output "role_grants" {
  value = { reader = var.grant_reader_role, seed = var.grant_seed_role }
}
output "runtime_configs" {
  value = local.runtime_configs
}
output "route_policy_state" {
  value = { pe_network_policies = var.pe_network_policies, install_pe_host_route = var.install_pe_host_route }
}
output "gate_state" {
  value = { dns_enabled = var.dns_enabled, pe_ingress_enabled = var.pe_ingress_enabled, client_paths_enabled = var.client_paths_enabled, seed_paths_enabled = var.seed_paths_enabled, allow_client_blob = var.allow_client_blob, allow_seed_blob = var.allow_seed_blob }
}
