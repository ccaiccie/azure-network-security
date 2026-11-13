# Gate 3 (deploy_security_admin): one security admin configuration, one rule collection that applies
# to the static group, and two rules. Admin rules are evaluated BEFORE NSG rules.
#   r-block-mgmt: Deny inbound TCP 22 and 3389 from the Internet service tag (a typical guardrail).
#   r-app-port:   var.admin_rule_action on var.app_port from the VirtualNetwork service tag.
# Lower priority number is evaluated first.

locals {
  sec_on = var.deploy_avnm && var.deploy_security_admin
}

resource "azurerm_network_manager_security_admin_configuration" "lab" {
  count              = local.sec_on ? 1 : 0
  name               = "sac-guardrails"
  network_manager_id = azurerm_network_manager.lab[0].id
  description        = "Study lab guardrails"
}

resource "azurerm_network_manager_admin_rule_collection" "lab" {
  count                           = local.sec_on ? 1 : 0
  name                            = "rc-spokes"
  security_admin_configuration_id = azurerm_network_manager_security_admin_configuration.lab[0].id
  network_group_ids               = [azurerm_network_manager_network_group.spokes[0].id]
  description                     = "Applies to the static spoke group"
}

resource "azurerm_network_manager_admin_rule" "block_mgmt" {
  count                    = local.sec_on ? 1 : 0
  name                     = "r-block-mgmt"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.lab[0].id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 10
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["22", "3389"]
  description              = "No management ports from the Internet"

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }

  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "0.0.0.0/0"
  }
}

resource "azurerm_network_manager_admin_rule" "app_port" {
  count                    = local.sec_on ? 1 : 0
  name                     = "r-app-port"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.lab[0].id
  action                   = var.admin_rule_action
  direction                = "Inbound"
  priority                 = 20
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = [tostring(var.app_port)]
  description              = "The action is the lab switch admin_rule_action"

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "VirtualNetwork"
  }

  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "0.0.0.0/0"
  }
}
