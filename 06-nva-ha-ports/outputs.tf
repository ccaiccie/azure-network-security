output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "location" {
  value = try(module.lab[0].location, null)
}
output "lb_id" {
  value = try(module.lab[0].lb_id, null)
}
output "lb_name" {
  value = try(module.lab[0].lb_name, null)
}
output "lb_frontend_ip" {
  value = try(module.lab[0].lb_frontend_ip, null)
}
output "app_vm_id" {
  value = try(module.lab[0].app_vm_id, null)
}
output "backend_vm_id" {
  value = try(module.lab[0].backend_vm_id, null)
}
output "nva_vm_ids" {
  value = try(module.lab[0].nva_vm_ids, null)
}
output "nic_ids" {
  value = try(module.lab[0].nic_ids, null)
}
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
}
output "admin_username" {
  value = try(module.lab[0].admin_username, null)
}
output "image_id" {
  value = try(module.lab[0].image_id, null)
}
output "nva_zones" {
  value = try(module.lab[0].nva_zones, null)
}
output "deployment_enabled" {
  value = var.deploy_lab
}
