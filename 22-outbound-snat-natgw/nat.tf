# Gate 2 (deploy_nat_gateway): NAT gateway attached to snet-nat (and optionally to snet-fw).

resource "azurerm_public_ip" "nat" {
  count               = var.deploy_nat_gateway && var.nat_public_ip_prefix_length == 0 ? 1 : 0
  name                = "${var.name_prefix}-nat-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_public_ip_prefix" "nat" {
  count               = var.deploy_nat_gateway && var.nat_public_ip_prefix_length != 0 ? 1 : 0
  name                = "${var.name_prefix}-nat-prefix"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  prefix_length       = var.nat_public_ip_prefix_length
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "lab" {
  count                   = var.deploy_nat_gateway ? 1 : 0
  name                    = "${var.name_prefix}-natgw"
  location                = azurerm_resource_group.lab.location
  resource_group_name     = azurerm_resource_group.lab.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_idle_timeout_minutes
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "lab" {
  count                = var.deploy_nat_gateway && var.nat_public_ip_prefix_length == 0 ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.lab[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "lab" {
  count               = var.deploy_nat_gateway && var.nat_public_ip_prefix_length != 0 ? 1 : 0
  nat_gateway_id      = azurerm_nat_gateway.lab[0].id
  public_ip_prefix_id = azurerm_public_ip_prefix.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "nat" {
  count          = var.deploy_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.nat.id
  nat_gateway_id = azurerm_nat_gateway.lab[0].id
}

# Optional: the same gateway on snet-fw, to show that a UDR to the firewall still wins.
resource "azurerm_subnet_nat_gateway_association" "fw" {
  count          = var.deploy_nat_gateway && var.nat_on_fw_subnet ? 1 : 0
  subnet_id      = azurerm_subnet.fw.id
  nat_gateway_id = azurerm_nat_gateway.lab[0].id
}
