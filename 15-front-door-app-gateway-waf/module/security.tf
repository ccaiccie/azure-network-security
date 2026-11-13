resource "azurerm_network_security_group" "gateway" {
  name                = "gateway-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_network_security_rule" "frontdoor" {
  name                        = "frontdoor-backend-https"
  priority                    = 100
  direction                   = "Inbound"
  access                      = var.gateway_ingress_enabled ? "Allow" : "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "AzureFrontDoor.Backend"
  destination_address_prefix  = "10.60.1.0/24"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.gateway.name
}
resource "azurerm_network_security_rule" "diagnostic" {
  name                        = "approved-fdid-diagnostic"
  priority                    = 110
  direction                   = "Inbound"
  access                      = var.fdid_diagnostic_ingress_enabled ? "Allow" : "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.operator_cidr
  destination_address_prefix  = "10.60.1.0/24"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.gateway.name
}
resource "azurerm_network_security_rule" "manager" {
  name                        = "required-gateway-manager"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "65200-65535"
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.gateway.name
}
resource "azurerm_network_security_rule" "platform_probe" {
  name                        = "required-platform-probe"
  priority                    = 210
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.gateway.name
}
resource "azurerm_network_security_rule" "deny_inbound" {
  name                        = "deny-other-inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.gateway.name
}
# Conventional public WAF_v2 requires outbound Internet/platform access.
# No deny-all outbound, default None route, VM-style forwarding or hidden NIC.
resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.gateway.id
  depends_on = [
    azurerm_network_security_rule.frontdoor,
    azurerm_network_security_rule.diagnostic,
    azurerm_network_security_rule.manager,
    azurerm_network_security_rule.platform_probe,
    azurerm_network_security_rule.deny_inbound
  ]
}
