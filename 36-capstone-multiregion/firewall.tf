# REFERENCE SKELETON: Azure Firewall policy (gate 4) and the firewalls themselves (gate 6, billable).
# One base policy holds the rules every region shares; each region has a child policy that inherits it.
# The rules are examples, not a complete rule base: check current Microsoft docs for rule syntax and limits.

resource "azurerm_resource_group" "global" {
  count    = var.deploy_firewall_policy ? 1 : 0
  name     = "${var.name_prefix}-global-rg"
  location = var.location_a
  tags     = local.tags
}

resource "azurerm_firewall_policy" "base" {
  count               = var.deploy_firewall_policy ? 1 : 0
  name                = "${var.name_prefix}-fwp-base"
  resource_group_name = azurerm_resource_group.global[0].name
  location            = var.location_a
  sku                 = "Premium"
  tags                = local.tags

  intrusion_detection {
    mode = "Alert"
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "base" {
  count              = var.deploy_firewall_policy ? 1 : 0
  name               = "rcg-base"
  firewall_policy_id = azurerm_firewall_policy.base[0].id
  priority           = 200

  network_rule_collection {
    name     = "net-core"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "dns-to-resolvers"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["10.20.0.0/15", "10.22.0.0/15"]
      destination_addresses = ["10.20.1.0/28", "10.22.1.0/28"]
      destination_ports     = ["53"]
    }
    rule {
      name                  = "web-to-app-8443"
      protocols             = ["TCP"]
      source_addresses      = ["10.20.5.0/24", "10.22.5.0/24"]
      destination_addresses = ["10.20.8.0/24", "10.22.8.0/24"]
      destination_ports     = ["8443"]
    }
    rule {
      name                  = "app-to-private-endpoints"
      protocols             = ["TCP"]
      source_addresses      = ["10.20.5.0/24", "10.22.5.0/24", "10.20.8.0/24", "10.22.8.0/24"]
      destination_addresses = ["10.20.9.0/24", "10.22.9.0/24"]
      destination_ports     = ["443"]
    }
    rule {
      name                  = "onprem-to-web-https"
      protocols             = ["TCP"]
      source_addresses      = ["10.200.0.0/16"]
      destination_addresses = ["10.20.5.0/24", "10.22.5.0/24"]
      destination_ports     = ["443"]
    }
  }

  application_rule_collection {
    name     = "app-egress"
    priority = 300
    action   = "Allow"

    rule {
      name = "os-updates"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["10.20.0.0/15", "10.22.0.0/15"]
      destination_fqdns = ["updates.example.net"]
    }
    rule {
      name = "aks-required-fqdns"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses      = ["10.20.16.0/22", "10.22.16.0/22"]
      destination_fqdn_tags = ["AzureKubernetesService"]
    }
  }
}

resource "azurerm_firewall_policy" "region" {
  for_each            = var.deploy_firewall_policy ? local.regions : {}
  name                = "${var.name_prefix}-fwp-${each.key}"
  resource_group_name = azurerm_resource_group.region[each.key].name
  location            = each.value.location
  sku                 = "Premium"
  base_policy_id      = azurerm_firewall_policy.base[0].id
  tags                = local.tags

  # DNS proxy lets the firewall answer spoke queries and use FQDNs in network rules.
  # The server is the regional resolver inbound endpoint (address reserved in the plan).
  dns {
    proxy_enabled = true
    servers       = [each.key == "a" ? "10.20.1.4" : "10.22.1.4"]
  }
}

resource "azurerm_public_ip" "firewall" {
  for_each            = var.deploy_firewalls ? local.regions : {}
  name                = "${var.name_prefix}-pip-fw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_firewall" "hub" {
  for_each            = var.deploy_firewalls ? local.regions : {}
  name                = "${var.name_prefix}-fw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.region[each.key].id
  zones               = ["1", "2", "3"]
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.hub["${each.key}/AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall[each.key].id
  }

  lifecycle {
    precondition {
      condition     = var.deploy_firewall_policy
      error_message = "Gate 6 needs gate 4 (deploy_firewall_policy)."
    }
  }
}
