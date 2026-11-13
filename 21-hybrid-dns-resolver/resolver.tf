# Gate 1 (deploy_resolver): the DNS Private Resolver, one inbound endpoint and one outbound endpoint.
# Both endpoints are billed per hour while they exist; check current pricing.

resource "azurerm_private_dns_resolver" "hub" {
  count               = var.deploy_resolver ? 1 : 0
  name                = "${var.name_prefix}-resolver"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.tags
}

# The inbound endpoint is the listener on-premises DNS forwards to. A fixed address keeps the forwarders stable.
resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  count                   = var.deploy_resolver ? 1 : 0
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = azurerm_resource_group.lab.location
  tags                    = local.tags

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = local.inbound_ip
    subnet_id                    = azurerm_subnet.dns_in.id
  }
}

# The outbound endpoint is where forwarded queries leave Azure. It has no IP you point anything at.
resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  count                   = var.deploy_resolver ? 1 : 0
  name                    = "outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = azurerm_resource_group.lab.location
  subnet_id               = azurerm_subnet.dns_out.id
  tags                    = local.tags
}
