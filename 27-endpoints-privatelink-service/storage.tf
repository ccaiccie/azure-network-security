# Gate 2 (deploy_storage): the lab storage account. Firewall default action Deny, one VNet rule for snet-se,
# trusted-service bypass off, and a container that allows anonymous listing so a plain curl is a clean test:
#   200 = the firewall let the request through, 403 AuthorizationFailure = the firewall blocked it.
# Lab only: anonymous container access is switched on for the test. Never do this with real data.
# Gate 4 (deploy_se_policy): a service endpoint policy on snet-se and a second account in its own resource group.
#   break_fix = public_open   sets the default action to Allow, so the account is open to the Internet

resource "random_string" "suffix" {
  count   = var.deploy_storage || var.deploy_se_policy ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "lab" {
  count                           = var.deploy_storage ? 1 : 0
  name                            = "${var.name_prefix}lab${random_string.suffix[0].result}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true
  public_network_access_enabled   = !var.disable_public_access
  tags                            = local.tags

  network_rules {
    default_action             = var.break_fix == "public_open" ? "Allow" : "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.se.id]
    ip_rules                   = var.admin_source_ip == "" ? [] : [var.admin_source_ip]
    bypass                     = ["None"]
  }
}

# The container is created through the management plane (storage_account_id), so a Deny firewall does not
# block Terraform. Check the provider docs for the minimum version that supports storage_account_id.
resource "azurerm_storage_container" "lab" {
  count                 = var.deploy_storage ? 1 : 0
  name                  = "labdata"
  storage_account_id    = azurerm_storage_account.lab[0].id
  container_access_type = "container"
}

# ---------------------------------------------------------------- gate 4

resource "azurerm_subnet_service_endpoint_storage_policy" "lab" {
  count               = var.deploy_se_policy ? 1 : 0
  name                = "${var.name_prefix}-sep"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  definition {
    name              = "allow-lab-resource-group"
    service           = "Microsoft.Storage"
    service_resources = [azurerm_resource_group.lab.id]
    description       = "Only storage accounts in the lab resource group are reachable over the service endpoint."
  }
}

resource "azurerm_resource_group" "other" {
  count    = var.deploy_se_policy ? 1 : 0
  name     = "${var.name_prefix}-other-rg"
  location = var.location
  tags     = local.tags
}

# The stand-in for an attacker's account: public, default Allow, outside the policy's resource group.
resource "azurerm_storage_account" "other" {
  count                           = var.deploy_se_policy ? 1 : 0
  name                            = "${var.name_prefix}oth${random_string.suffix[0].result}"
  location                        = azurerm_resource_group.other[0].location
  resource_group_name             = azurerm_resource_group.other[0].name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true
  tags                            = local.tags
}

resource "azurerm_storage_container" "other" {
  count                 = var.deploy_se_policy ? 1 : 0
  name                  = "otherdata"
  storage_account_id    = azurerm_storage_account.other[0].id
  container_access_type = "container"
}
