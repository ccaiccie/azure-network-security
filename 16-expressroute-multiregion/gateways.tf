# One ExpressRoute gateway per hub. Billable by the hour and slow to deploy (deploy_er_gateways).

resource "azurerm_public_ip" "er_gateway" {
  for_each = local.gateways

  name                = "${var.name_prefix}-ergw-pip-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab[0].name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.public_ip_zones
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "er" {
  for_each = local.gateways

  name                = "${var.name_prefix}-ergw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab[0].name
  type                = "ExpressRoute"
  sku                 = var.er_gateway_sku
  tags                = local.tags

  ip_configuration {
    name                          = "gateway-ip"
    public_ip_address_id          = azurerm_public_ip.er_gateway[each.key].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[each.key].id
  }
}
