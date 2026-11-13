# Optional: metrics to Log Analytics, so BGP and ARP availability can be queried with KQL.

resource "azurerm_log_analytics_workspace" "this" {
  count = var.deploy_lab && var.enable_diagnostics ? 1 : 0

  name                = "${var.name_prefix}-logs"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.lab[0].name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "circuit" {
  for_each = var.deploy_lab && var.enable_diagnostics ? azurerm_express_route_circuit.this : {}

  name                       = "to-logs"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "gateway" {
  for_each = var.deploy_lab && var.enable_diagnostics ? azurerm_virtual_network_gateway.er : {}

  name                       = "to-logs"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id

  enabled_metric {
    category = "AllMetrics"
  }
}
