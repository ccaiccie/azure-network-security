output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "route_server_name" {
  description = "Name of Route Server (empty without gate 1)."
  value       = try(azurerm_route_server.rs[0].name, "")
}

output "route_server_asn" {
  description = "ASN of Route Server. Fixed by the platform (65515; check current docs)."
  value       = try(azurerm_route_server.rs[0].virtual_router_asn, "")
}

output "route_server_ips" {
  description = "The two Route Server peer addresses in RouteServerSubnet. Both NVAs must peer with both."
  value       = try(azurerm_route_server.rs[0].virtual_router_ips, [])
}

output "nva_private_ips" {
  description = "Addresses of the FRR NVAs."
  value       = { "nva-a" = "10.37.1.4", "nva-b" = "10.37.1.5" }
}

output "nva_public_ips" {
  description = "Public IPs of the NVAs (outbound only; no inbound rule exists)."
  value       = { for k, p in azurerm_public_ip.nva : k => p.ip_address }
}

output "app_ip" {
  description = "Address of vm-app, whose effective routes show the learned prefixes."
  value       = "10.37.2.4"
}

output "vpn_gateway_name" {
  description = "Name of the VPN gateway (empty without gate 3)."
  value       = try(azurerm_virtual_network_gateway.vpn[0].name, "")
}
