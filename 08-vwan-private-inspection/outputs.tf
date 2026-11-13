output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "location" {
  value = try(module.lab[0].location, null)
}
output "vwan_id" {
  value = try(module.lab[0].vwan_id, null)
}
output "hub_id" {
  value = try(module.lab[0].hub_id, null)
}
output "hub_name" {
  value = try(module.lab[0].hub_name, null)
}
output "hub_default_route_table_id" {
  value = try(module.lab[0].hub_default_route_table_id, null)
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
output "firewall_public_ips" {
  value = try(module.lab[0].firewall_public_ips, null)
}
output "firewall_policy_id" {
  value = try(module.lab[0].firewall_policy_id, null)
}
output "routing_intent_id" {
  value = try(module.lab[0].routing_intent_id, null)
}
output "connection_ids" {
  value = try(module.lab[0].connection_ids, null)
}
output "app_vm_id" {
  value = try(module.lab[0].app_vm_id, null)
}
output "backend_vm_id" {
  value = try(module.lab[0].backend_vm_id, null)
}
output "nic_ids" {
  value = try(module.lab[0].nic_ids, null)
}
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
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
output "deployment_enabled" {
  value = var.deploy_lab
}
