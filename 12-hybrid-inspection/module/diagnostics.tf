resource "azurerm_log_analytics_workspace" "lab" {
  name                         = "hybrid-logs"
  resource_group_name          = azurerm_resource_group.lab.name
  location                     = azurerm_resource_group.lab.location
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "hybrid-evidence"
  target_resource_id             = azurerm_firewall.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  dynamic "enabled_log" {
    for_each = toset(["AZFWNetworkRule", "AZFWThreatIntel"])
    content { category = enabled_log.key }
  }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  for_each                   = local.gateways
  name                       = "${each.key}-vpn-evidence"
  target_resource_id         = azurerm_virtual_network_gateway.lab[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  # VPN diagnostic records use AzureDiagnostics. No packet capture or PSK read.
  dynamic "enabled_log" {
    for_each = toset(["GatewayDiagnosticLog", "TunnelDiagnosticLog", "RouteDiagnosticLog"])
    content { category = enabled_log.key }
  }
  enabled_metric { category = "AllMetrics" }
}
