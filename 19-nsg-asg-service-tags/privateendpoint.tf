# Gate 3 (deploy_private_endpoint): a storage account with a blob private endpoint in snet-pe.
# Private DNS is left out on purpose: the activities use the endpoint's IP address.
# The subnet's network policies setting is in main.tf (var.pe_network_policies).

resource "random_string" "suffix" {
  count   = var.deploy_private_endpoint || var.enable_flow_logs ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "target" {
  count                    = var.deploy_private_endpoint ? 1 : 0
  name                     = "${var.name_prefix}pe${random_string.suffix[0].result}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "${var.name_prefix}-pe-blob"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.target[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  depends_on = [azurerm_subnet_network_security_group_association.pe]
}
