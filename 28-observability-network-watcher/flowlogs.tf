# Gate 3 (deploy_flow_logs): virtual network flow logs on the client and server VNets.
# They write JSON to the storage account and, when traffic_analytics_enabled is true, to Traffic Analytics.
# Argument names (target_resource_id for VNet flow logs) depend on the azurerm version: check the provider docs.

locals {
  flow_targets = var.deploy_flow_logs && var.deploy_monitoring ? {
    client = azurerm_virtual_network.client.id
    server = azurerm_virtual_network.server.id
  } : {}
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  for_each             = local.flow_targets
  name                 = "${var.name_prefix}-fl-${each.key}"
  network_watcher_name = local.watcher_name
  resource_group_name  = local.watcher_rg
  target_resource_id   = each.value
  storage_account_id   = azurerm_storage_account.logs[0].id
  enabled              = true
  version              = 2
  tags                 = local.tags

  retention_policy {
    enabled = true
    days    = 7
  }

  dynamic "traffic_analytics" {
    for_each = var.traffic_analytics_enabled ? [1] : []
    content {
      enabled               = true
      workspace_id          = azurerm_log_analytics_workspace.lab[0].workspace_id
      workspace_region      = azurerm_log_analytics_workspace.lab[0].location
      workspace_resource_id = azurerm_log_analytics_workspace.lab[0].id
      interval_in_minutes   = var.traffic_analytics_interval
    }
  }
}
