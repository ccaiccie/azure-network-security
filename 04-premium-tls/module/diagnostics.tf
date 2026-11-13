resource "azurerm_log_analytics_workspace" "lab" {
  name                         = "tls-logs"
  resource_group_name          = azurerm_resource_group.lab.name
  location                     = azurerm_resource_group.lab.location
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "tls-evidence"
  target_resource_id             = azurerm_firewall.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  dynamic "enabled_log" {
    for_each = toset(["AZFWApplicationRule", "AZFWNetworkRule", "AZFWDnsQuery", "AZFWIdpsSignature", "AZFWThreatIntel"])
    content { category = enabled_log.key }
  }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_diagnostic_setting" "origin" {
  name                           = "origin-evidence"
  target_resource_id             = azurerm_linux_web_app.origin.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceIPSecAuditLogs"])
    content { category = enabled_log.key }
  }
}
