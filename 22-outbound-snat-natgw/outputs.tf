output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "vnet_name" {
  description = "Name of the lab VNet."
  value       = azurerm_virtual_network.lab.name
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT gateway (empty without gate 2, or when a prefix is used)."
  value       = try(azurerm_public_ip.nat[0].ip_address, "")
}

output "nat_gateway_prefix" {
  description = "Public IP prefix of the NAT gateway (empty unless nat_public_ip_prefix_length is set)."
  value       = try(azurerm_public_ip_prefix.nat[0].ip_prefix, "")
}

output "lb_frontend_ip" {
  description = "Frontend public IP of the outbound load balancer (empty without gate 3)."
  value       = try(azurerm_public_ip.lb[0].ip_address, "")
}

output "firewall_public_ip" {
  description = "Public IP of Azure Firewall (empty without gate 4)."
  value       = try(azurerm_public_ip.fw[0].ip_address, "")
}

output "vm_nat_public_ip" {
  description = "Instance-level public IP of vm-nat (empty without gate 5)."
  value       = try(azurerm_public_ip.vm_nat[0].ip_address, "")
}
