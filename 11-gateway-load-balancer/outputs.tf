output "deployment_enabled" {
  value = var.deploy_lab
}
output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "location" {
  value = try(module.lab[0].location, null)
}
output "gwlb_id" {
  value = try(module.lab[0].gwlb_id, null)
}
output "gwlb_frontend_id" {
  value = try(module.lab[0].gwlb_frontend_id, null)
}
output "gwlb_frontend_private_ip" {
  value = try(module.lab[0].gwlb_frontend_private_ip, null)
}
output "consumer_lb_id" {
  value = try(module.lab[0].consumer_lb_id, null)
}
output "consumer_frontend_id" {
  value = try(module.lab[0].consumer_frontend_id, null)
}
output "consumer_public_ip_id" {
  value = try(module.lab[0].consumer_public_ip_id, null)
}
output "consumer_public_ip" {
  value = try(module.lab[0].consumer_public_ip, null)
}
output "client_public_ip" {
  value = try(module.lab[0].client_public_ip, null)
}
output "backend_private_ip" {
  value = try(module.lab[0].backend_private_ip, null)
}
output "nva_pool_id" {
  value = try(module.lab[0].nva_pool_id, null)
}
output "app_pool_id" {
  value = try(module.lab[0].app_pool_id, null)
}
output "probe_ids" {
  value = try(module.lab[0].probe_ids, null)
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
output "vnet_ids" {
  value = try(module.lab[0].vnet_ids, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
}
output "bastion_id" {
  value = try(module.lab[0].bastion_id, null)
}
output "admin_username" {
  value = try(module.lab[0].admin_username, null)
}
output "image_id" {
  value = try(module.lab[0].image_id, null)
}
output "chain_enabled" {
  value = try(module.lab[0].chain_enabled, null)
}
output "test_nsg_action" {
  value = try(module.lab[0].test_nsg_action, null)
}
