# Gate 1: the user route of the web subnet. The next hop is the internal load balancer frontend, never one firewall NIC.
# The default route is removed while the Gateway LB variant (gate 3) is on, because replies to the chained frontend must
# leave by their own path. The peering adds a more specific system route for 10.80.0.0/16, so replies to the firewall's
# trust address do not use this route.

resource "azurerm_route" "web_default" {
  count                  = var.deploy_firewalls && !var.deploy_gateway_lb ? 1 : 0
  name                   = "default-to-ilb"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.web.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.ilb_frontend_ip
}
