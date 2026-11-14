output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "public_frontend_ip" {
  description = "Public address of the public load balancer (the lab guide shows it as 203.0.113.80)."
  value       = one(azurerm_public_ip.plb[*].ip_address)
}

output "gateway_frontend_public_ip" {
  description = "Public address of the second frontend chained to the Gateway LB (shown as 203.0.113.81)."
  value       = one(azurerm_public_ip.gw_web[*].ip_address)
}

output "public_lb_id" {
  value = one(azurerm_lb.public[*].id)
}

output "internal_lb_id" {
  value = one(azurerm_lb.internal[*].id)
}

output "ilb_frontend_ip" {
  value = var.ilb_frontend_ip
}

output "firewall_mgmt_public_ips" {
  description = "Management public IPs; reachable only from mgmt_source_cidr."
  value       = { for k, v in azurerm_public_ip.mgmt : k => v.ip_address }
}
