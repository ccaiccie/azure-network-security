output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "gwlb_id" {
  value = azurerm_lb.inspection.id
}
output "gwlb_frontend_id" {
  value = one(azurerm_lb.inspection.frontend_ip_configuration).id
}
output "gwlb_frontend_private_ip" {
  value = local.gwlb_ip
}
output "consumer_lb_id" {
  value = azurerm_lb.consumer.id
}
output "consumer_frontend_id" {
  value = one(azurerm_lb.consumer.frontend_ip_configuration).id
}
output "consumer_public_ip_id" {
  value = azurerm_public_ip.consumer.id
}
output "consumer_public_ip" {
  value = azurerm_public_ip.consumer.ip_address
}
output "client_public_ip" {
  value = var.client_public_ip
}
output "backend_private_ip" {
  value = local.backend_ip
}
output "nva_pool_id" {
  value = azurerm_lb_backend_address_pool.nvas.id
}
output "app_pool_id" {
  value = azurerm_lb_backend_address_pool.app.id
}
output "probe_ids" {
  value = { nva = azurerm_lb_probe.nva.id, app = azurerm_lb_probe.app.id }
}
output "vm_ids" {
  value = { for k, v in azurerm_linux_virtual_machine.vm : k => v.id }
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.vm : k => v.id }
}
output "private_ips" {
  value = { for k, v in local.nodes : k => v.ip }
}
output "vnet_ids" {
  value = { for k, v in azurerm_virtual_network.lab : k => v.id }
}
output "bastion_name" {
  value = azurerm_bastion_host.lab.name
}
output "bastion_id" {
  value = azurerm_bastion_host.lab.id
}
output "admin_username" {
  value = var.admin_username
}
output "image_id" {
  value = var.image_id
}
output "chain_enabled" {
  value = var.enable_chain
}
output "test_nsg_action" {
  value = local.test_nsg_action
}
