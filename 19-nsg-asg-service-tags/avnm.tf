# Gate 5 (enable_avnm_demo): one Virtual Network Manager security admin rule that denies inbound TCP 23 (telnet)
# from the Internet to every VNet in one network group (here only this lab's VNet).
# A security admin rule is evaluated BEFORE any NSG and is not visible in the NSG's own rule list.
# Check the current provider docs: resource and block names below were written from memory and not validated.

data "azurerm_subscription" "current" {}

resource "azurerm_network_manager" "lab" {
  count               = var.enable_avnm_demo ? 1 : 0
  name                = "${var.name_prefix}-avnm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  scope_accesses      = ["SecurityAdmin"]
  tags                = local.tags

  scope {
    subscription_ids = [data.azurerm_subscription.current.id]
  }
}

resource "azurerm_network_manager_network_group" "lab" {
  count              = var.enable_avnm_demo ? 1 : 0
  name               = "ng-nsg-lab"
  network_manager_id = azurerm_network_manager.lab[0].id
}

resource "azurerm_network_manager_static_member" "lab" {
  count                     = var.enable_avnm_demo ? 1 : 0
  name                      = "member-lab-vnet"
  network_group_id          = azurerm_network_manager_network_group.lab[0].id
  target_virtual_network_id = azurerm_virtual_network.lab.id
}

resource "azurerm_network_manager_security_admin_configuration" "lab" {
  count              = var.enable_avnm_demo ? 1 : 0
  name               = "sac-nsg-lab"
  network_manager_id = azurerm_network_manager.lab[0].id
}

resource "azurerm_network_manager_admin_rule_collection" "lab" {
  count                           = var.enable_avnm_demo ? 1 : 0
  name                            = "arc-no-telnet"
  security_admin_configuration_id = azurerm_network_manager_security_admin_configuration.lab[0].id
  network_group_ids               = [azurerm_network_manager_network_group.lab[0].id]
}

resource "azurerm_network_manager_admin_rule" "deny_telnet" {
  count                    = var.enable_avnm_demo ? 1 : 0
  name                     = "deny-telnet-from-internet"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.lab[0].id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 10
  protocol                 = "Tcp"
  destination_port_ranges  = ["23"]

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }

  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "10.30.0.0/16"
  }
}

# A configuration only takes effect after it is deployed to a region.
resource "azurerm_network_manager_deployment" "lab" {
  count              = var.enable_avnm_demo ? 1 : 0
  network_manager_id = azurerm_network_manager.lab[0].id
  location           = azurerm_resource_group.lab.location
  scope_access       = "SecurityAdmin"
  configuration_ids  = [azurerm_network_manager_security_admin_configuration.lab[0].id]

  depends_on = [azurerm_network_manager_admin_rule.deny_telnet]
}
