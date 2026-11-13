output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "address_plan" {
  description = "The address space of every VNet in the lab."
  value = {
    "vnet-hub"     = local.hub_space
    "vnet-spoke-a" = local.spoke_a_space
    "vnet-spoke-b" = local.spoke_b_space
    "vnet-spoke-c" = var.create_global_peering ? local.spoke_c_space : "not created"
  }
}

output "vm_private_ips" {
  value = { for k, v in local.vms : k => v.ip }
}

output "nva_private_ip" {
  value = var.deploy_nva ? local.nva_ip : null
}

output "peering_links" {
  description = "Each link and the four properties set on it."
  value = {
    hub_to_a = {
      access = azurerm_virtual_network_peering.hub_to_a.allow_virtual_network_access
      fwd    = azurerm_virtual_network_peering.hub_to_a.allow_forwarded_traffic
      gwt    = azurerm_virtual_network_peering.hub_to_a.allow_gateway_transit
      rgw    = azurerm_virtual_network_peering.hub_to_a.use_remote_gateways
    }
    a_to_hub = {
      access = azurerm_virtual_network_peering.a_to_hub.allow_virtual_network_access
      fwd    = azurerm_virtual_network_peering.a_to_hub.allow_forwarded_traffic
      gwt    = azurerm_virtual_network_peering.a_to_hub.allow_gateway_transit
      rgw    = azurerm_virtual_network_peering.a_to_hub.use_remote_gateways
    }
  }
}

output "gateway_public_ip" {
  value = var.create_gateway ? azurerm_public_ip.gateway[0].ip_address : null
}
