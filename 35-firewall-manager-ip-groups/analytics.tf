# Gate 2: a workspace for policy analytics and logs. The policy insights block is in policies.tf.
# The diagnostic setting needs a firewall (gate 1). Use resource-specific tables (a dedicated destination type) so that
# the AZFW* tables carry the Policy, RuleCollectionGroup, RuleCollection and Rule columns (check current docs).

resource "azurerm_log_analytics_workspace" "lab" {
  count               = var.deploy_analytics ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count                          = var.deploy_analytics && local.firewall_on ? 1 : 0
  name                           = "diag-firewall"
  target_resource_id             = azurerm_firewall.lab[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab[0].id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWNatRule"
  }
}
