resource "azurerm_log_analytics_workspace" "lab" {
  name                         = "waf-observability"
  resource_group_name          = azurerm_resource_group.lab.name
  location                     = azurerm_resource_group.lab.location
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  name                           = "gateway-evidence"
  target_resource_id             = azurerm_application_gateway.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "edge-evidence"
  target_resource_id         = azurerm_cdn_frontdoor_profile.lab.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  enabled_log { category = "FrontDoorAccessLog" }
  enabled_log { category = "FrontDoorWebApplicationFirewallLog" }
  enabled_log { category = "FrontDoorHealthProbeLog" }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_diagnostic_setting" "backend" {
  name                           = "backend-evidence"
  target_resource_id             = azurerm_linux_web_app.backend.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceIPSecAuditLogs" }
  enabled_metric { category = "AllMetrics" }
}
