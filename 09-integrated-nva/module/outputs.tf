output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "location" {
  value = azurerm_resource_group.lab.location
}
output "vwan_id" {
  value = azurerm_virtual_wan.lab.id
}
output "hub_id" {
  value = azurerm_virtual_hub.lab.id
}
output "hub_name" {
  value = azurerm_virtual_hub.lab.name
}
output "hub_default_route_table_id" {
  value = azurerm_virtual_hub.lab.default_route_table_id
}
output "connection_id" {
  value = azurerm_virtual_hub_connection.app.id
}
output "routing_intent_id" {
  value = try(azurerm_virtual_hub_routing_intent.internet[0].id, null)
}
output "nva_resource_id" {
  value = try(var.vendor_profile.nva_resource_id, null)
}
output "vendor_profile" {
  value = var.vendor_profile
}
output "origin_public_ip" {
  value = azurerm_public_ip.origin.ip_address
}
output "origin_public_ip_id" {
  value = azurerm_public_ip.origin.id
}
output "egress_public_ips" {
  value = sort(tolist(var.egress_public_ips))
}
output "app_vm_id" {
  value = azurerm_linux_virtual_machine.vm["app"].id
}
output "origin_vm_id" {
  value = azurerm_linux_virtual_machine.vm["origin"].id
}
output "nic_ids" {
  value = { for k, v in azurerm_network_interface.vm : k => v.id }
}
output "private_ips" {
  value = { app = local.app_ip, origin = local.origin_ip }
}
output "bastion_names" {
  value = { for k, v in azurerm_bastion_host.lab : k => v.name }
}
output "admin_username" {
  value = var.admin_username
}
output "image_id" {
  value = var.image_id
}
output "test_nsg_action" {
  value = local.test_nsg_action
}
output "internet_intent_enabled" {
  value = var.enable_internet_intent
}
output "management_vnet_id" {
  value = azurerm_virtual_network.management.id
}
