output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "location" {
  value = try(module.lab[0].location, null)
}
output "firewall_id" {
  value = try(module.lab[0].firewall_id, null)
}
output "firewall_name" {
  value = try(module.lab[0].firewall_name, null)
}
output "firewall_private_ip" {
  value = try(module.lab[0].firewall_private_ip, null)
}
output "firewall_public_ip" {
  value = try(module.lab[0].firewall_public_ip, null)
}
output "firewall_policy_id" {
  value = try(module.lab[0].firewall_policy_id, null)
}
output "vnet_ids" {
  value = try(module.lab[0].vnet_ids, null)
}
output "gateway_ids" {
  value = try(module.lab[0].gateway_ids, null)
}
output "gateway_public_ips" {
  value = try(module.lab[0].gateway_public_ips, null)
}
output "gateway_public_ip_ids" {
  value = try(module.lab[0].gateway_public_ip_ids, null)
}
output "connection_ids" {
  value = try(module.lab[0].connection_ids, null)
}
output "vm_ids" {
  value = try(module.lab[0].vm_ids, null)
}
output "nic_ids" {
  value = try(module.lab[0].nic_ids, null)
}
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
}
output "route_table_ids" {
  value = try(module.lab[0].route_table_ids, null)
}
output "bastion_ids" {
  value = try(module.lab[0].bastion_ids, null)
}
output "bastion_names" {
  value = try(module.lab[0].bastion_names, null)
}
output "admin_username" {
  value = try(module.lab[0].admin_username, null)
}
output "image_id" {
  value = try(module.lab[0].image_id, null)
}
output "workspace_id" {
  value = try(module.lab[0].workspace_id, null)
}
output "workspace_customer_id" {
  value = try(module.lab[0].workspace_customer_id, null)
}
output "test_firewall_action" {
  value = try(module.lab[0].test_firewall_action, null)
}
output "test_nsg_action" {
  value = try(module.lab[0].test_nsg_action, null)
}
output "connections_enabled" {
  value = try(module.lab[0].connections_enabled, null)
}
output "deployment_enabled" {
  value = var.deploy_lab
}
