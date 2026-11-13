# Free baseline: resource group, the Virtual WAN object and the spoke VNets.
# A Virtual WAN resource on its own has no hourly charge (check current pricing); the hubs in hub.tf are what bill.

locals {
  tags = merge({ lab = "azure-32-vwan-routing", purpose = "study" }, var.tags)

  spokes = {
    prod   = { cidr = "10.101.0.0/24", region = 1 }
    dev    = { cidr = "10.102.0.0/24", region = 1 }
    shared = { cidr = "10.103.0.0/24", region = 1 }
    eu2    = { cidr = "10.201.0.0/24", region = 2 }
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Standard is required for ExpressRoute, hub-to-hub, custom route tables and VNet transit. Basic is VPN site-to-site only.
resource "azurerm_virtual_wan" "wan" {
  name                           = "${var.name_prefix}-wan"
  resource_group_name            = azurerm_resource_group.lab.name
  location                       = azurerm_resource_group.lab.location
  type                           = "Standard"
  allow_branch_to_branch_traffic = var.allow_branch_to_branch
  tags                           = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = "${var.name_prefix}-spoke-${each.key}"
  location            = each.value.region == 1 ? var.location : var.location2
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [each.value.cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "spoke" {
  for_each             = local.spokes
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.cidr]
}
