# COSTLY (gate 3): a DDoS protection plan. Roughly thousands of US dollars per month
# and billed from creation, linked or not (check current Azure pricing).
# Two switches are needed on purpose: deploy_ddos_network_protection and accept_ddos_plan_cost.

resource "azurerm_network_ddos_protection_plan" "lab" {
  count               = local.plan_on ? 1 : 0
  name                = "${var.name_prefix}-plan"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
