# The parent (central) policy and two child (application) policies. Every rule group has a number in its name
# that is also its priority, so the order is visible in the portal and in the logs.
# Attribute names come from provider documentation knowledge: check the azurerm docs for your provider version.

resource "azurerm_firewall_policy" "parent" {
  name                     = "${var.name_prefix}-fp-parent"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  sku                      = var.policy_sku
  threat_intelligence_mode = "Alert"
  tags                     = local.tags

  dns {
    proxy_enabled = true
  }

  # Premium only (check current docs): IDPS on the parent so children inherit it unless they set their own.
  dynamic "intrusion_detection" {
    for_each = local.premium ? [1] : []
    content {
      mode = "Alert"
    }
  }

  # Policy analytics needs a workspace (gate 2).
  dynamic "insights" {
    for_each = var.deploy_analytics ? [1] : []
    content {
      enabled                            = true
      default_log_analytics_workspace_id = azurerm_log_analytics_workspace.lab[0].id
      retention_in_days                  = var.log_retention_days
    }
  }
}

# ---------------------------------------------------------------- parent rule collection groups

resource "azurerm_firewall_policy_rule_collection_group" "parent_dnat" {
  name               = "rcg-100-central-dnat"
  firewall_policy_id = azurerm_firewall_policy.parent.id
  priority           = 100

  nat_rule_collection {
    name     = "nat-central-portal"
    priority = 100
    action   = "Dnat"

    rule {
      name                = "dnat-portal-443"
      protocols           = ["TCP"]
      source_addresses    = ["*"]
      destination_address = var.dnat_public_ip
      destination_ports   = ["443"]
      translated_address  = "10.60.8.10"
      translated_port     = 443
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "parent_net" {
  name               = "rcg-200-central-network"
  firewall_policy_id = azurerm_firewall_policy.parent.id
  priority           = 200

  network_rule_collection {
    name     = "nc-central-deny"
    priority = 100
    action   = "Deny"

    rule {
      name                  = "deny-known-bad"
      protocols             = ["TCP", "UDP"]
      source_ip_groups      = [azurerm_ip_group.spokes.id]
      destination_ip_groups = [azurerm_ip_group.blocked.id]
      destination_ports     = ["*"]
    }
  }

  network_rule_collection {
    name     = "nc-central-allow"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-dns-shared"
      protocols             = ["UDP"]
      source_ip_groups      = [azurerm_ip_group.spokes.id]
      destination_addresses = ["10.60.8.53"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "allow-https-shared"
      protocols             = ["TCP"]
      source_ip_groups      = [azurerm_ip_group.spokes.id]
      destination_ip_groups = [azurerm_ip_group.shared.id]
      destination_ports     = ["443"]
    }
  }

  # Rule collection groups of one policy are updated one at a time: chain them.
  depends_on = [azurerm_firewall_policy_rule_collection_group.parent_dnat]
}

resource "azurerm_firewall_policy_rule_collection_group" "parent_app" {
  name               = "rcg-300-central-application"
  firewall_policy_id = azurerm_firewall_policy.parent.id
  priority           = 300

  application_rule_collection {
    name     = "ac-central-allow"
    priority = 100
    action   = "Allow"

    rule {
      name              = "allow-microsoft-https"
      source_ip_groups  = [azurerm_ip_group.spokes.id]
      destination_fqdns = ["*.microsoft.com"]

      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.parent_net]
}

# ---------------------------------------------------------------- child policy A

resource "azurerm_firewall_policy" "child_a" {
  name                = "${var.name_prefix}-fp-child-a"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = var.policy_sku
  base_policy_id      = azurerm_firewall_policy.parent.id
  tags                = local.tags

  # Settings that are not set here are inherited from the parent (check which settings the portal shows as inherited).
}

resource "azurerm_firewall_policy_rule_collection_group" "child_a" {
  name               = "rcg-100-app-a"
  firewall_policy_id = azurerm_firewall_policy.child_a.id
  priority           = 100

  network_rule_collection {
    name     = "nc-app-a-allow"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "app-a-to-sql"
      protocols             = ["TCP"]
      source_ip_groups      = [azurerm_ip_group.app_a.id]
      destination_ip_groups = [azurerm_ip_group.shared.id]
      destination_ports     = ["1433"]
    }
  }

  # Break/fix 1: a child allow for a range the parent denies first. It never matches.
  dynamic "network_rule_collection" {
    for_each = var.child_allow_blocked_range ? [1] : []
    content {
      name     = "nc-app-a-exception"
      priority = 50
      action   = "Allow"

      rule {
        name                  = "allow-partner-range"
        protocols             = ["TCP"]
        source_ip_groups      = [azurerm_ip_group.app_a.id]
        destination_ip_groups = [azurerm_ip_group.blocked.id]
        destination_ports     = ["443"]
      }
    }
  }

  # Break/fix 4: the same public IP and port as the parent DNAT rule, with a different target.
  dynamic "nat_rule_collection" {
    for_each = var.child_conflicting_dnat ? [1] : []
    content {
      name     = "nat-app-a-portal"
      priority = 100
      action   = "Dnat"

      rule {
        name                = "dnat-portal-443-app-a"
        protocols           = ["TCP"]
        source_addresses    = ["*"]
        destination_address = var.dnat_public_ip
        destination_ports   = ["443"]
        translated_address  = "10.61.1.20"
        translated_port     = 443
      }
    }
  }
}

# ---------------------------------------------------------------- child policy B

resource "azurerm_firewall_policy" "child_b" {
  name                     = "${var.name_prefix}-fp-child-b"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  sku                      = var.policy_sku
  base_policy_id           = azurerm_firewall_policy.parent.id
  threat_intelligence_mode = "Deny"
  tags                     = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "child_b" {
  name               = "rcg-100-app-b"
  firewall_policy_id = azurerm_firewall_policy.child_b.id
  priority           = 100

  network_rule_collection {
    name     = "nc-app-b-allow"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "app-b-to-postgres"
      protocols             = ["TCP"]
      source_ip_groups      = [azurerm_ip_group.app_b.id]
      destination_ip_groups = [azurerm_ip_group.shared.id]
      destination_ports     = ["5432"]
    }
  }
}
