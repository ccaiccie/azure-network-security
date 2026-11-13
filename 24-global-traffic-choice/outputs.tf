output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "lb_fqdn" {
  description = "DNS name of the load balancer's public IP (empty without gate 1)."
  value       = try(azurerm_public_ip.lb[0].fqdn, "")
}

output "appgw_fqdn" {
  description = "DNS name of the Application Gateway's public IP (empty without gate 2)."
  value       = try(azurerm_public_ip.agw[0].fqdn, "")
}

output "front_door_hostname" {
  description = "Default hostname of the Front Door endpoint (empty without gate 3)."
  value       = try(azurerm_cdn_frontdoor_endpoint.lab[0].host_name, "")
}

output "traffic_manager_fqdn" {
  description = "DNS name of the Traffic Manager profile (empty without gate 4)."
  value       = try(azurerm_traffic_manager_profile.lab[0].fqdn, "")
}
