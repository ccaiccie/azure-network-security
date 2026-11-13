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
output "firewall_policy_id" {
  value = try(module.lab[0].firewall_policy_id, null)
}
output "firewall_private_ip" {
  value = try(module.lab[0].firewall_private_ip, null)
}
output "bastion_id" {
  value = try(module.lab[0].bastion_id, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
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
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
}
output "endpoint_ip" {
  value = try(module.lab[0].endpoint_ip, null)
}
output "endpoint_id" {
  value = try(module.lab[0].endpoint_id, null)
}
output "endpoint_subnet_id" {
  value = try(module.lab[0].endpoint_subnet_id, null)
}
output "endpoint_nsg_id" {
  value = try(module.lab[0].endpoint_nsg_id, null)
}
output "route_table_id" {
  value = try(module.lab[0].route_table_id, null)
}
output "storage_account_id" {
  value = try(module.lab[0].storage_account_id, null)
}
output "storage_account_name" {
  value = try(module.lab[0].storage_account_name, null)
}
output "container_id" {
  value = try(module.lab[0].container_id, null)
}
output "container_name" {
  value = try(module.lab[0].container_name, null)
}
output "blob_name" {
  value = try(module.lab[0].blob_name, null)
}
output "blob_fqdn" {
  value = try(module.lab[0].blob_fqdn, null)
}
output "blob_url" {
  value = try(module.lab[0].blob_url, null)
}
output "private_dns_zone_id" {
  value = try(module.lab[0].private_dns_zone_id, null)
}
output "identity_principal_ids" {
  value = try(module.lab[0].identity_principal_ids, null)
}
output "role_assignment_ids" {
  value = try(module.lab[0].role_assignment_ids, null)
}
output "role_grants" {
  value = try(module.lab[0].role_grants, null)
}
output "runtime_configs" {
  value = try(module.lab[0].runtime_configs, null)
}
output "route_policy_state" {
  value = try(module.lab[0].route_policy_state, null)
}
output "gate_state" {
  value = try(module.lab[0].gate_state, null)
}
