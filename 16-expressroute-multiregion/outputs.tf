output "resource_group_name" {
  description = "Name of the lab resource group, or null while deploy_lab is false."
  value       = try(azurerm_resource_group.lab[0].name, null)
}

output "hub_vnet_ids" {
  description = "Hub VNet IDs by region key."
  value       = { for k, v in azurerm_virtual_network.hub : k => v.id }
}

output "er_gateway_names" {
  description = "ExpressRoute gateway names by region key."
  value       = { for k, v in azurerm_virtual_network_gateway.er : k => v.name }
}

output "circuit_names" {
  description = "Circuit names by key."
  value       = { for k, v in azurerm_express_route_circuit.this : k => v.name }
}

output "circuit_service_keys" {
  description = "Service keys. Give each to its provider; never paste them into tickets or chat."
  value       = { for k, v in azurerm_express_route_circuit.this : k => v.service_key }
  sensitive   = true
}

output "connection_names" {
  description = "Gateway connection names by key."
  value       = { for k, v in azurerm_virtual_network_gateway_connection.er : k => v.name }
}

output "vm_nic_names" {
  description = "Test VM NIC names, for the effective-routes command."
  value       = { for k, v in azurerm_network_interface.vm : k => v.name }
}

output "peering_plan" {
  description = "The example /30 plan, for checking your router against."
  value = {
    for k, c in var.circuits : k => {
      primary   = c.primary_peer_address_prefix
      secondary = c.secondary_peer_address_prefix
      vlan_id   = c.vlan_id
      peer_asn  = var.customer_asn
    }
  }
}
