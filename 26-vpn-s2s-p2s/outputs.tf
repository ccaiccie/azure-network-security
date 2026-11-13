output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "gateway_name" {
  description = "Name of the VPN gateway (empty without gate 1)."
  value       = try(azurerm_virtual_network_gateway.vpn[0].name, "")
}

output "gateway_public_ips" {
  description = "Public IP(s) of the VPN gateway: one when active-standby, two when active-active."
  value       = [for p in azurerm_public_ip.gw : p.ip_address]
}

output "gateway_bgp_ips" {
  description = "Azure-side BGP peer address(es) when BGP is on. With APIPA these are the 169.254.x.x addresses."
  value       = try(azurerm_virtual_network_gateway.vpn[0].bgp_settings[0].peering_addresses[*].default_addresses, [])
}

output "edge_public_ip" {
  description = "Public IP of vm-edge, the simulated on-premises VPN device (empty without gate 2)."
  value       = try(azurerm_public_ip.edge[0].ip_address, "")
}

output "connection_name" {
  description = "Name of the site-to-site connection (empty without gate 3)."
  value       = try(azurerm_virtual_network_gateway_connection.s2s[0].name, "")
}

output "onprem_lan_ip" {
  description = "Address of vm-lan, the host behind the simulated device."
  value       = "10.70.2.10"
}

output "app_ip" {
  description = "Address of vm-app, the host in the Azure VNet."
  value       = "10.60.1.10"
}
