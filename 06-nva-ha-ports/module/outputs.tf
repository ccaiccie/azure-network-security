output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "lb_id" {
  value = azurerm_lb.lab.id
}
output "lb_name" {
  value = azurerm_lb.lab.name
}
output "lb_frontend_ip" {
  value = local.frontend_ip
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.vm["app"].id
}
output "backend_vm_id" {
  value = azurerm_linux_virtual_machine.vm["backend"].id
}
output "nva_vm_ids" {
  value = { for k, v in local.nvas : k => azurerm_linux_virtual_machine.vm[k].id }
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.vm : k => v.id }
}
output "private_ips" {
  value = local.private_ips
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "admin_username" {
  value = var.admin_username
}
output "image_id" {
  value = var.image_id
}
output "nva_zones" {
  value = var.nva_zones
}
