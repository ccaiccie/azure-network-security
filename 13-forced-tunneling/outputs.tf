output "deployment_enabled" {
  value = var.deploy_lab
}
output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
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
output "firewall_policy_id" {
  value = try(module.lab[0].firewall_policy_id, null)
}
output "workspace_id" {
  value = try(module.lab[0].workspace_id, null)
}
output "workspace_customer_id" {
  value = try(module.lab[0].workspace_customer_id, null)
}
output "vm_ids" {
  value = try(module.lab[0].vm_ids, null)
}
output "nic_ids" {
  value = try(module.lab[0].nic_ids, null)
}
output "vnet_ids" {
  value = try(module.lab[0].vnet_ids, null)
}
output "route_table_ids" {
  value = try(module.lab[0].route_table_ids, null)
}
output "bastion_id" {
  value = try(module.lab[0].bastion_id, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
}
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
}
output "public_ips" {
  value = try(module.lab[0].public_ips, null)
}
output "public_ip_ids" {
  value = try(module.lab[0].public_ip_ids, null)
}
output "source_mode" {
  value = try(module.lab[0].source_mode, null)
}
output "perimeter_source_prefix" {
  value = try(module.lab[0].perimeter_source_prefix, null)
}
output "gate_state" {
  value = try(module.lab[0].gate_state, null)
}
output "runtime_configs" {
  value = try(module.lab[0].runtime_configs, null)
}
