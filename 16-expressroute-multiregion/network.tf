# Two hubs and two spokes, with the peering flags that let a spoke use its hub's gateway.

resource "azurerm_virtual_network" "hub" {
  for_each = local.lab

  name                = "${var.name_prefix}-hub-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab[0].name
  address_space       = [each.value.hub_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "gateway" {
  for_each = local.lab

  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab[0].name
  virtual_network_name = azurerm_virtual_network.hub[each.key].name
  address_prefixes     = [each.value.gw_cidr]
}

resource "azurerm_virtual_network" "spoke" {
  for_each = local.lab

  name                = "${var.name_prefix}-spoke-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab[0].name
  address_space       = [each.value.spoke_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "workload" {
  for_each = local.lab

  name                 = "workload"
  resource_group_name  = azurerm_resource_group.lab[0].name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.wl_cidr]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = local.lab

  name                         = "hub-to-spoke-${each.key}"
  resource_group_name          = azurerm_resource_group.lab[0].name
  virtual_network_name         = azurerm_virtual_network.hub[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.deploy_er_gateways
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = local.lab

  name                         = "spoke-to-hub-${each.key}"
  resource_group_name          = azurerm_resource_group.lab[0].name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.deploy_er_gateways

  # The spoke can only use the remote gateway once the hub gateway exists.
  depends_on = [azurerm_virtual_network_gateway.er]
}
