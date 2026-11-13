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
output "app_vm_id" {
  value = try(module.lab[0].app_vm_id, null)
}
output "app_nic_id" {
  value = try(module.lab[0].app_nic_id, null)
}
output "app_private_ip" {
  value = try(module.lab[0].app_private_ip, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
}
output "admin_username" {
  value = try(module.lab[0].admin_username, null)
}
output "origin_name" {
  value = try(module.lab[0].origin_name, null)
}
output "origin_id" {
  value = try(module.lab[0].origin_id, null)
}
output "origin_hostname" {
  value = try(module.lab[0].origin_hostname, null)
}
output "workspace_id" {
  value = try(module.lab[0].workspace_id, null)
}
output "workspace_customer_id" {
  value = try(module.lab[0].workspace_customer_id, null)
}
output "operator_cidr" {
  value = try(module.lab[0].operator_cidr, null)
}
output "image_version" {
  value = try(module.lab[0].image_version, null)
}
output "readiness_flags" {
  value = try(module.lab[0].readiness_flags, null)
}
output "deployment_enabled" {
  value = var.deploy_lab
}
