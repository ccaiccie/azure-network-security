# Gate 3 (deploy_private_endpoint, needs deploy_storage): a blob private endpoint, the Private Link zone,
# its link to the consumer VNet and (normally) a zone group on the endpoint.
#   break_fix = pe_pending     makes the connection manual, so it waits for approval
#   break_fix = zone_unlinked  leaves out the zone's link to the VNet, so the name resolves to the public IP
# DNS is only a dependency here: the details of zones, links and zone groups are covered elsewhere.

locals {
  pe_on = var.deploy_storage && var.deploy_private_endpoint
}

resource "azurerm_private_dns_zone" "blob" {
  count               = local.pe_on ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_con" {
  count                 = local.pe_on && var.break_fix != "zone_unlinked" ? 1 : 0
  name                  = "link-blob-con"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.con.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  count               = local.pe_on ? 1 : 0
  name                = "${var.name_prefix}-pe-blob"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.tags

  # A static address keeps the expected outputs in the guide stable.
  ip_configuration {
    name               = "blob"
    private_ip_address = "10.50.2.5"
    subresource_name   = "blob"
  }

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.lab[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = var.break_fix == "pe_pending"
    request_message                = var.break_fix == "pe_pending" ? "Please approve the lab endpoint" : null
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}
