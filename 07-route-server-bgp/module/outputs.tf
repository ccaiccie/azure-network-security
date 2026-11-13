output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "route_server_id" {
  value = azurerm_route_server.lab.id
}
output "route_server_name" {
  value = azurerm_route_server.lab.name
}
output "route_server_peer_ips" {
  value = local.rs_peer_ips
}
output "route_server_asn" {
  value = local.rs_asn
}
output "route_server_routing_state" {
  value = azurerm_route_server.lab.routing_state
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.vm["app"].id
}
output "remote_vm_id" {
  value = azurerm_linux_virtual_machine.vm["remote"].id
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
output "destination_ip" {
  value = local.destination_ip
}
output "destination_prefix" {
  value = local.destination_prefix
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
output "frr_version" {
  value = var.frr_version
}
