# Free network objects: resource group, VNet, one subnet and its NSG.
# Nothing in this file bills by the hour. The VNet carries the DDoS plan link
# only when gate 3 is open and link_vnet_to_plan is true.

locals {
  tags = merge({ lab = "azure-29-ddos-protection", purpose = "study" }, var.tags)

  # Gate 3 needs BOTH switches, so one typo cannot create an expensive plan.
  plan_on     = var.deploy_ddos_network_protection && var.accept_ddos_plan_cost
  plan_linked = local.plan_on && var.link_vnet_to_plan
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.90.0.0/16"]
  tags                = local.tags

  # Network Protection: link the VNet to the plan. Public IPs of resources in this VNet inherit protection.
  dynamic "ddos_protection_plan" {
    for_each = local.plan_linked ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.lab[0].id
      enable = true
    }
  }
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.90.1.0/24"]
}

# The NSG answers a different question from DDoS protection: who may reach which port.
resource "azurerm_network_security_group" "web" {
  name                = "${var.name_prefix}-nsg-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-web-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}
