resource "azurerm_log_analytics_workspace" "lab" {
  name                         = "law-egress"
  resource_group_name          = azurerm_resource_group.lab.name
  location                     = azurerm_resource_group.lab.location
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
  # No daily cap: a cap can silently remove the evidence the demo needs.
  # Control spending through runtime duration and approved Azure cost alerts.
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "firewall-to-workspace"
  target_resource_id             = azurerm_firewall.egress.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset([
      "AZFWNetworkRule",
      "AZFWApplicationRule",
      "AZFWDnsQuery",
      "AZFWThreatIntel"
    ])
    content {
      category = enabled_log.key
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
