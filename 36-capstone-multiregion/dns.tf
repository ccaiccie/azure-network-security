# REFERENCE SKELETON: private DNS zone links (gate 5) and DNS Private Resolver (gate 7, billable).
# One private zone is linked to the HUB VNets only. Spokes ask the firewall (DNS proxy), the firewall asks the
# resolver inbound endpoint in the hub, and the hub's own Azure DNS answers from the linked zone.

resource "azurerm_resource_group" "dns" {
  count    = var.link_private_dns ? 1 : 0
  name     = "${var.name_prefix}-dns-rg"
  location = var.location_a
  tags     = local.tags
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.link_private_dns ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.dns[0].name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = var.link_private_dns ? local.regions : {}
  name                  = "link-hub-${each.key}"
  resource_group_name   = azurerm_resource_group.dns[0].name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.hub[each.key].id
  registration_enabled  = false
  tags                  = local.tags
}

# Example of the mistake the guide warns about: do NOT also link every spoke. One spoke link is shown so that
# you can compare the effective answer from a linked and an unlinked VNet in the activities.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke_web_a" {
  count                 = var.link_private_dns && var.deploy_region_a ? 1 : 0
  name                  = "link-spoke-a-web"
  resource_group_name   = azurerm_resource_group.dns[0].name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.spoke["a-web"].id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_resolver" "hub" {
  for_each            = var.deploy_resolvers ? local.regions : {}
  name                = "${var.name_prefix}-dnspr-${each.key}"
  resource_group_name = azurerm_resource_group.region[each.key].name
  location            = each.value.location
  virtual_network_id  = azurerm_virtual_network.hub[each.key].id
  tags                = local.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  for_each                = var.deploy_resolvers ? local.regions : {}
  name                    = "inbound-${each.key}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[each.key].id
  location                = each.value.location
  tags                    = local.tags

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = each.key == "a" ? "10.20.1.4" : "10.22.1.4"
    subnet_id                    = azurerm_subnet.hub["${each.key}/snet-dns-in"].id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  for_each                = var.deploy_resolvers ? local.regions : {}
  name                    = "outbound-${each.key}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[each.key].id
  location                = each.value.location
  subnet_id               = azurerm_subnet.hub["${each.key}/snet-dns-out"].id
  tags                    = local.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  for_each                                   = var.deploy_resolvers ? local.regions : {}
  name                                       = "${var.name_prefix}-ruleset-${each.key}"
  resource_group_name                        = azurerm_resource_group.region[each.key].name
  location                                   = each.value.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub[each.key].id]
  tags                                       = local.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "corp" {
  for_each                  = var.deploy_resolvers ? local.regions : {}
  name                      = "corp-example-com"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[each.key].id
  domain_name               = "corp.example.com."
  enabled                   = true

  target_dns_servers {
    ip_address = var.onprem_dns_ip
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  for_each                  = var.deploy_resolvers ? local.regions : {}
  name                      = "ruleset-link-hub-${each.key}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[each.key].id
  virtual_network_id        = azurerm_virtual_network.hub[each.key].id
}
