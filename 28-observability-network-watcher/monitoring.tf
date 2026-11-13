# Gate 2 (deploy_monitoring): a Log Analytics workspace and a storage account for flow logs and packet captures.
# Both bill for what they hold; the workspace keeps data for 30 days here (the default). Check current pricing.

resource "random_string" "suffix" {
  count   = var.deploy_monitoring ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_log_analytics_workspace" "lab" {
  count               = var.deploy_monitoring ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_storage_account" "logs" {
  count                           = var.deploy_monitoring ? 1 : 0
  name                            = "${var.name_prefix}st${random_string.suffix[0].result}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}
