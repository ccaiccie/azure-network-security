output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "gateway_name" {
  value = try(azurerm_virtual_network_gateway.er[0].name, "")
}

output "gateway_public_ip" {
  value = try(azurerm_public_ip.er[0].ip_address, "")
}

output "circuit_id" {
  description = "Empty until a circuit exists or existing_circuit_id is set."
  value       = local.circuit_id
}

output "connection_name" {
  value = try(azurerm_virtual_network_gateway_connection.er[0].name, "")
}

output "vm_private_ip" {
  value = try(azurerm_network_interface.app[0].private_ip_address, "")
}
