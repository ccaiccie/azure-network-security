# Gate 1: the ExpressRoute gateway. Billed by the hour and slow to create.
# AZ SKUs need a zone-redundant Standard public IP.

resource "azurerm_public_ip" "er" {
  count               = var.deploy_er_gateway ? 1 : 0
  name                = "${var.name_prefix}-er-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "er" {
  count               = var.deploy_er_gateway ? 1 : 0
  name                = "${var.name_prefix}-ergw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "ExpressRoute"
  sku                 = var.gateway_sku
  tags                = local.tags

  ip_configuration {
    name                          = "default"
    public_ip_address_id          = azurerm_public_ip.er[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}
