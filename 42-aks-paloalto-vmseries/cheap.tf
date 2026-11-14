# Gate 3: NSG rules on the node subnets. They are free. They stop A reaching any port in B, which the default
# AllowVnetInBound rule would otherwise allow because peered ranges count as VirtualNetwork.

resource "azurerm_network_security_rule" "a_to_orders" {
  count                       = var.enable_cheap_layer ? 1 : 0
  name                        = "allow-web-to-orders"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "10.71.0.0/22"
  destination_address_prefix  = "10.72.0.100/32"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.aks_a.name
}

resource "azurerm_network_security_rule" "a_deny_b" {
  count                       = var.enable_cheap_layer ? 1 : 0
  name                        = "deny-rest-of-b"
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "10.71.0.0/22"
  destination_address_prefix  = "10.72.0.0/16"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.aks_a.name
}

resource "azurerm_network_security_rule" "b_from_firewall" {
  count                       = var.enable_cheap_layer ? 1 : 0
  name                        = "allow-from-firewall-nat"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "10.70.2.4/31"
  destination_address_prefix  = "10.72.0.100/32"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.aks_b.name
}

resource "azurerm_network_security_rule" "b_lb_probe" {
  count                       = var.enable_cheap_layer ? 1 : 0
  name                        = "allow-lb-probe"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.aks_b.name
}

resource "azurerm_network_security_rule" "b_deny_vnet" {
  count                       = var.enable_cheap_layer ? 1 : 0
  name                        = "deny-other-peered-sources"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "10.72.0.0/22"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.aks_b.name
}
