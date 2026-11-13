output "resource_group" {
  description = "Resource group of the lab."
  value       = azurerm_resource_group.lab.name
}

output "hub1_id" {
  description = "Resource ID of hub 1 (empty until gate 1)."
  value       = local.hub1_id
}

output "hub1_router_ips" {
  description = "Virtual hub router IPs of hub 1 (the BGP peering targets for an NVA). The router ASN is 65515."
  value       = try(azurerm_virtual_hub.hub1[0].virtual_router_ips, [])
}

output "route_table_ids_hub1" {
  description = "Hub 1 route tables: the Default and None tables always exist; rt-spokes and rt-branch are created by the lab."
  value = local.hub1_on ? {
    default   = local.h1_default
    none      = local.h1_none
    rt_spokes = local.rt_spokes
    rt_branch = local.rt_branch
  } : {}
}

output "hub2_id" {
  description = "Resource ID of hub 2 (empty until gate 5)."
  value       = local.hub2_id
}

output "edge_public_ip" {
  description = "Public IP of vm-edge (the VPN site address), empty until gate 3."
  value       = try(azurerm_public_ip.edge[0].ip_address, "")
}

output "vpn_gateway_bgp_ips" {
  description = "BGP addresses of the two hub VPN gateway instances (the documentation examples until gate 4)."
  value       = local.gw_bgp_ips
}

output "vm_private_ips" {
  description = "Private IPs of the lab VMs, for the ping tests."
  value       = { for k, v in local.vms_on : k => v.ip }
}
