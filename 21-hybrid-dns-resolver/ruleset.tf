# Gate 2 (deploy_ruleset, needs deploy_resolver): the forwarding ruleset, two rules and the VNet links.

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "hub" {
  count                                      = var.deploy_resolver && var.deploy_ruleset ? 1 : 0
  name                                       = "${var.name_prefix}-ruleset"
  location                                   = azurerm_resource_group.lab.location
  resource_group_name                        = azurerm_resource_group.lab.name
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub[0].id]
  tags                                       = local.tags
}

# Rule 1: names under corp.example.com go to the on-premises DNS server (the dot at the end is required).
resource "azurerm_private_dns_resolver_forwarding_rule" "corp" {
  count                     = var.deploy_resolver && var.deploy_ruleset ? 1 : 0
  name                      = "corp-to-onprem"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  domain_name               = local.corp_domain
  enabled                   = true

  target_dns_servers {
    ip_address = var.corp_forward_target
    port       = 53
  }
}

# Rule 2: a more specific name that is switched off, to show that a disabled rule is skipped.
resource "azurerm_private_dns_resolver_forwarding_rule" "old" {
  count                     = var.deploy_resolver && var.deploy_ruleset ? 1 : 0
  name                      = "old-corp-disabled"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  domain_name               = "old.corp.example.com."
  enabled                   = false

  target_dns_servers {
    ip_address = "10.60.1.11"
    port       = 53
  }
}

# A ruleset only applies to VNets it is linked to. No peering is needed for a link.
resource "azurerm_private_dns_resolver_virtual_network_link" "spoke" {
  count                     = var.deploy_resolver && var.deploy_ruleset && var.link_spoke_to_ruleset ? 1 : 0
  name                      = "link-spoke"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  virtual_network_id        = azurerm_virtual_network.spoke.id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  count                     = var.deploy_resolver && var.deploy_ruleset && var.link_hub_to_ruleset ? 1 : 0
  name                      = "link-hub"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.hub[0].id
  virtual_network_id        = azurerm_virtual_network.hub.id
}
