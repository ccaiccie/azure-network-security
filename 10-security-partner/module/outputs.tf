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
output "vpn_gateway_id" {
  value = azurerm_vpn_gateway.lab.id
}
output "vpn_gateway_name" {
  value = azurerm_vpn_gateway.lab.name
}
output "spp_id" {
  value = try(azurerm_virtual_hub_security_partner_provider.lab[0].id, null)
}
output "provider_profile" {
  value = var.provider_profile
}
output "origin_public_ips" {
  value = { for k, v in azurerm_public_ip.origin : k => v.ip_address }
}
output "origin_public_ip_ids" {
  value = { for k, v in azurerm_public_ip.origin : k => v.id }
}
output "egress_public_ips" {
  value = sort(tolist(var.egress_public_ips))
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
output "bastion_names" {
  value = { for k, v in azurerm_bastion_host.lab : k => v.name }
}
output "management_vnet_id" {
  value = azurerm_virtual_network.management.id
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
output "source_default_enabled" {
  value = var.enable_source_default
}
output "spp_enabled" {
  value = var.enable_spp
}
output "vpn_gateway_public_ips" {
  description = "Computed gateway endpoint candidates; pair with actual provider tunnel/edge evidence, not E web egress."
  value       = [for config in azurerm_vpn_gateway.lab.ip_configuration : config.public_ip_address]
}
