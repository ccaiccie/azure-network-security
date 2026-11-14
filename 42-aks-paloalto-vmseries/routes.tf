# Gate 1: the user routes. Every next hop is the ILB frontend, never a single firewall NIC.
# With a pod subnet (Azure CNI dynamic IP allocation) associate the same route table with the pod subnet too.

resource "azurerm_route" "a_to_b" {
  count                  = var.deploy_firewalls ? 1 : 0
  name                   = "to-cluster-b"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.a.name
  address_prefix         = "10.72.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.ilb_frontend_ip
}

resource "azurerm_route" "a_default" {
  count                  = var.deploy_firewalls ? 1 : 0
  name                   = "default-to-ilb"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.a.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.ilb_frontend_ip
}

# Break/fix case 3: set b_reply_next_hop_override to a firewall trust address to bypass the ILB on purpose.
resource "azurerm_route" "b_to_a" {
  count                  = var.deploy_firewalls ? 1 : 0
  name                   = "to-cluster-a"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.b.name
  address_prefix         = "10.71.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.b_reply_next_hop_override != "" ? var.b_reply_next_hop_override : var.ilb_frontend_ip
}

resource "azurerm_route" "b_default" {
  count                  = var.deploy_firewalls ? 1 : 0
  name                   = "default-to-ilb"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.b.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.ilb_frontend_ip
}
