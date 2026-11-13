# Commit (deploy) configurations to regions. A configuration does nothing until it is deployed.
# One deployment per region and scope access. Deploying another configuration of the same type
# to a region REPLACES what was committed there: that is how a rollback works.

locals {
  active_conn_id = local.conn_on ? (var.active_connectivity == "v1" ? azurerm_network_manager_connectivity_configuration.v1[0].id : azurerm_network_manager_connectivity_configuration.v2[0].id) : ""
}

resource "azurerm_network_manager_deployment" "connectivity" {
  for_each           = local.conn_on ? toset(var.deployment_regions) : toset([])
  network_manager_id = azurerm_network_manager.lab[0].id
  location           = each.value
  scope_access       = "Connectivity"
  configuration_ids  = [local.active_conn_id]

  triggers = {
    configuration = local.active_conn_id
  }
}

resource "azurerm_network_manager_deployment" "security" {
  for_each           = local.sec_on ? toset(var.deployment_regions) : toset([])
  network_manager_id = azurerm_network_manager.lab[0].id
  location           = each.value
  scope_access       = "SecurityAdmin"
  configuration_ids  = [azurerm_network_manager_security_admin_configuration.lab[0].id]

  triggers = {
    rule_action = var.admin_rule_action
    rules       = join(",", [azurerm_network_manager_admin_rule.block_mgmt[0].id, azurerm_network_manager_admin_rule.app_port[0].id])
  }

  depends_on = [
    azurerm_network_manager_admin_rule.block_mgmt,
    azurerm_network_manager_admin_rule.app_port,
  ]
}
