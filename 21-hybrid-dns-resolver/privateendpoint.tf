# Gate 4 (deploy_private_endpoint): a storage account with a blob private endpoint in the hub, the
# privatelink zone, and the zone's link to the hub VNet. The zone is linked to the HUB only. That is the point:
# the spoke and on-premises reach the record through the resolver, not through their own zone links.

resource "random_string" "suffix" {
  count   = var.deploy_private_endpoint ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "target" {
  count                    = var.deploy_private_endpoint ? 1 : 0
  name                     = "${var.name_prefix}st${random_string.suffix[0].result}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  count                 = var.deploy_private_endpoint ? 1 : 0
  name                  = "link-hub"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags
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

  # This registers the A record in the zone for you.
  private_dns_zone_group {
    name                 = "blob-zone"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}
