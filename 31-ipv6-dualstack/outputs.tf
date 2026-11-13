output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "web_v4" {
  value = var.deploy_vms ? "10.31.1.10" : null
}

output "web_v6" {
  description = "Private IPv6 address of vm-web-1 (assigned dynamically by Azure)."
  value       = var.deploy_vms ? azurerm_network_interface.vm["vm-web-1"].private_ip_addresses[1] : null
}

output "lb_v4" {
  value = local.lb_on ? azurerm_public_ip.lb_v4[0].ip_address : null
}

output "lb_v6" {
  value = local.lb_on ? azurerm_public_ip.lb_v6[0].ip_address : null
}

output "client_public_v4" {
  value = var.deploy_vms && var.deploy_client_ips ? azurerm_public_ip.client_v4[0].ip_address : null
}

output "client_public_v6" {
  value = var.deploy_vms && var.deploy_client_ips ? azurerm_public_ip.client_v6[0].ip_address : null
}
