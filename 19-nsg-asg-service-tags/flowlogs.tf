# Gate 4 (enable_flow_logs): a virtual network flow log written to a storage account.
# New NSG flow logs can no longer be created and the NSG flow log feature is scheduled for retirement,
# so the lab uses a virtual network flow log. Check the current Microsoft docs and the provider docs:
# the attribute names below (target_resource_id) need a recent azurerm.

data "azurerm_network_watcher" "regional" {
  count               = var.enable_flow_logs ? 1 : 0
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

resource "azurerm_storage_account" "flow" {
  count                    = var.enable_flow_logs ? 1 : 0
  name                     = "${var.name_prefix}fl${random_string.suffix[0].result}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  count                = var.enable_flow_logs ? 1 : 0
  name                 = "${var.name_prefix}-vnet-flowlog"
  network_watcher_name = data.azurerm_network_watcher.regional[0].name
  resource_group_name  = data.azurerm_network_watcher.regional[0].resource_group_name
  location             = azurerm_resource_group.lab.location
  target_resource_id   = azurerm_virtual_network.lab.id
  storage_account_id   = azurerm_storage_account.flow[0].id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }
}
