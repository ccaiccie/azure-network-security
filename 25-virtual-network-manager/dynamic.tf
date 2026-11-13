# Gate 4 (deploy_dynamic_group): dynamic membership. An Azure Policy with the addToNetworkGroup effect
# adds every VNet whose env tag equals "prod" to a second network group. The policy is assigned at the
# subscription, so it is org-style plumbing: that is why it sits behind a gate.
# Evaluation is not instant: after a tag change, wait for the compliance scan or trigger one.

locals {
  dyn_on = var.deploy_avnm && var.deploy_dynamic_group
}

resource "azurerm_network_manager_network_group" "dynamic" {
  count              = local.dyn_on ? 1 : 0
  name               = "ng-prod-dynamic"
  network_manager_id = azurerm_network_manager.lab[0].id
  description        = "Dynamic group: VNets tagged env = prod (filled by Azure Policy)"
}

resource "azurerm_policy_definition" "prod_vnets" {
  count        = local.dyn_on ? 1 : 0
  name         = "${var.name_prefix}-add-prod-vnets"
  policy_type  = "Custom"
  mode         = "Microsoft.Network.Data"
  display_name = "AVNM lab: add VNets tagged env=prod to the dynamic network group"

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Network/virtualNetworks" },
        { field = "tags['env']", equals = "prod" }
      ]
    }
    then = {
      effect = "addToNetworkGroup"
      details = {
        networkGroupId = azurerm_network_manager_network_group.dynamic[0].id
      }
    }
  })
}

resource "azurerm_subscription_policy_assignment" "prod_vnets" {
  count                = local.dyn_on ? 1 : 0
  name                 = "${var.name_prefix}-prod-vnets"
  display_name         = "AVNM lab: dynamic group for prod VNets"
  policy_definition_id = azurerm_policy_definition.prod_vnets[0].id
  subscription_id      = data.azurerm_subscription.current.id
}
