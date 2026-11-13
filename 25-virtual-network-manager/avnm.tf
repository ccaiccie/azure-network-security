# Gate 1 (deploy_avnm): the network manager and the static network group.
# Scope is this subscription. Scope accesses decide which feature families the manager may use.
# Nothing here changes any VNet until a configuration is committed (deploy.tf).

data "azurerm_subscription" "current" {}

resource "azurerm_network_manager" "lab" {
  count               = var.deploy_avnm ? 1 : 0
  name                = "${var.name_prefix}-avnm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  scope_accesses      = ["Connectivity", "SecurityAdmin"]
  description         = "Study lab network manager"
  tags                = local.tags

  scope {
    subscription_ids = [data.azurerm_subscription.current.id]
  }
}

# Static membership: the spokes are added by hand.
resource "azurerm_network_manager_network_group" "spokes" {
  count              = var.deploy_avnm ? 1 : 0
  name               = "ng-spokes-static"
  network_manager_id = azurerm_network_manager.lab[0].id
  description        = "Static group: spoke-a, spoke-b and (gate 6) spoke-d"
}

resource "azurerm_network_manager_static_member" "a" {
  count                     = var.deploy_avnm ? 1 : 0
  name                      = "member-spoke-a"
  network_group_id          = azurerm_network_manager_network_group.spokes[0].id
  target_virtual_network_id = azurerm_virtual_network.a.id
}

resource "azurerm_network_manager_static_member" "b" {
  count                     = var.deploy_avnm ? 1 : 0
  name                      = "member-spoke-b"
  network_group_id          = azurerm_network_manager_network_group.spokes[0].id
  target_virtual_network_id = azurerm_virtual_network.b.id
}

resource "azurerm_network_manager_static_member" "d" {
  count                     = var.deploy_avnm && var.deploy_second_region ? 1 : 0
  name                      = "member-spoke-d"
  network_group_id          = azurerm_network_manager_network_group.spokes[0].id
  target_virtual_network_id = azurerm_virtual_network.d[0].id
}
