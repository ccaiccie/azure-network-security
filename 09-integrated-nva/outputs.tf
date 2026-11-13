output "deployment_enabled" {
  value = var.deploy_lab
}
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
output "connection_id" {
  value = try(module.lab[0].connection_id, null)
}
output "routing_intent_id" {
  value = try(module.lab[0].routing_intent_id, null)
}
output "nva_resource_id" {
  value = try(module.lab[0].nva_resource_id, null)
}
output "vendor_profile" {
  value = try(module.lab[0].vendor_profile, null)
}
output "origin_public_ip" {
  value = try(module.lab[0].origin_public_ip, null)
}
output "origin_public_ip_id" {
  value = try(module.lab[0].origin_public_ip_id, null)
}
output "egress_public_ips" {
  value = try(module.lab[0].egress_public_ips, null)
}
output "app_vm_id" {
  value = try(module.lab[0].app_vm_id, null)
}
output "origin_vm_id" {
  value = try(module.lab[0].origin_vm_id, null)
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
output "test_nsg_action" {
  value = try(module.lab[0].test_nsg_action, null)
}
output "internet_intent_enabled" {
  value = try(module.lab[0].internet_intent_enabled, null)
}
output "management_vnet_id" {
  value = try(module.lab[0].management_vnet_id, null)
}
