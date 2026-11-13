resource "azurerm_storage_account" "lab" {
  name                             = var.storage_account_name
  resource_group_name              = azurerm_resource_group.lab.name
  location                         = azurerm_resource_group.lab.location
  account_kind                     = "StorageV2"
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  access_tier                      = "Hot"
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  public_network_access            = "Disabled"
  shared_access_key_enabled        = false
  allow_nested_items_to_be_public  = false
  default_to_oauth_authentication  = true
  local_user_enabled               = false
  is_hns_enabled                   = false
  sftp_enabled                     = false
  nfsv3_enabled                    = false
  cross_tenant_replication_enabled = false
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }
  blob_properties {
    versioning_enabled  = false
    change_feed_enabled = false
    delete_retention_policy { days = 1 }
    container_delete_retention_policy { days = 1 }
  }
  tags = local.tags
}
resource "azurerm_storage_container" "lab" {
  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.lab.id
  container_access_type = "private"
  # ARM container only; no azurerm_storage_blob or Terraform data-plane secret bootstrap.
  # Pinned provider behavior still requires offline schema and approved runtime verification.
}
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  name                 = "hub-blob-resolution"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = azurerm_virtual_network.lab["hub"].id
  registration_enabled = false
  resolution_policy    = "Default"
  tags                 = local.tags
}
resource "azurerm_private_endpoint" "blob" {
  name                          = "blob-pe"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  subnet_id                     = azurerm_subnet.endpoint.id
  custom_network_interface_name = "blob-pe-nic"
  private_service_connection {
    name                           = "owned-blob"
    private_connection_resource_id = azurerm_storage_account.lab.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  ip_configuration {
    name               = "blob-static"
    private_ip_address = local.endpoint_ip
    subresource_name   = "blob"
    member_name        = "blob"
  }
  private_dns_zone_group {
    name                 = "owned-blob-zone"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
  tags       = local.tags
  depends_on = [azurerm_subnet_network_security_group_association.endpoint]
}
locals {
  data_roles = {
    reader = { enabled = var.grant_reader_role, role = "Storage Blob Data Reader" }
    seed   = { enabled = var.grant_seed_role, role = "Storage Blob Data Contributor" }
  }
}
resource "azurerm_role_assignment" "blob" {
  for_each                         = { for role, value in local.data_roles : role => value if value.enabled }
  scope                            = azurerm_storage_container.lab.id
  role_definition_name             = each.value.role
  principal_id                     = azurerm_linux_virtual_machine.client[each.key].identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  # Persistent access: requires explicit authorized operator action, never executed here.
}
