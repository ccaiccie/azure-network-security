# Gate 3 (deploy_private_endpoint): a storage account, a blob private endpoint, the Private Link zone
# privatelink.blob.core.windows.net, its links, and (normally) a zone group on the endpoint.
#   break_fix = no_zone_group   leaves out the zone group, so nothing writes the A record
#   break_fix = pe_zone_unlinked leaves out the zone's link to the spoke VNet

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

# The app VNet always resolves the Private Link zone. It is a resolution link: the endpoint's record
# comes from the zone group, not from autoregistration.
resource "azurerm_private_dns_zone_virtual_network_link" "blob_app" {
  count                 = var.deploy_private_endpoint ? 1 : 0
  name                  = "link-blob-app"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.app.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_spoke" {
  count                 = var.deploy_private_endpoint && var.break_fix != "pe_zone_unlinked" ? 1 : 0
  name                  = "link-blob-spoke"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "${var.name_prefix}-pe-blob"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.app_pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.target[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # The zone group is what writes and later removes the endpoint's A record in the zone.
  dynamic "private_dns_zone_group" {
    for_each = var.break_fix == "no_zone_group" ? [] : [1]
    content {
      name                 = "default"
      private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
    }
  }
}
