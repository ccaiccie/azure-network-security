# Free network objects: resource group, hub VNet with AzureBastionSubnet and its NSG, spoke VNet with snet-app.
# Nothing in this file bills by the hour. Bastion, the VM and the Defender plan are in their own gated files.

locals {
  tags = merge({ lab = "azure-33-bastion-jit", purpose = "study" }, var.tags)

  bastion_subnet_prefix = "10.33.250.0/26"

  # Gates 2 and 3 each need BOTH switches, so one typo cannot create something expensive.
  bastion_on  = var.deploy_bastion && var.accept_bastion_cost && var.deploy_workload
  defender_on = var.deploy_defender_servers && var.accept_defender_cost
  # Bastion features that need Standard or higher (check current Microsoft docs).
  bastion_std = contains(["Standard", "Premium"], var.bastion_sku)

  # The commonly documented NSG rule set for AzureBastionSubnet (check the current Bastion NSG page).
  bastion_in_rules = concat([
    { name = "allow-https-internet", priority = 120, source = "Internet", ports = ["443"], dest = "*" },
    { name = "allow-lb-probe", priority = 140, source = "AzureLoadBalancer", ports = ["443"], dest = "*" },
    { name = "allow-data-plane-in", priority = 150, source = "VirtualNetwork", ports = ["8080", "5701"], dest = "VirtualNetwork" },
    ],
    # Break/fix 1: set bastion_nsg_include_gatewaymanager = false to remove the control plane rule.
    var.bastion_nsg_include_gatewaymanager ? [
      { name = "allow-gatewaymanager", priority = 130, source = "GatewayManager", ports = ["443"], dest = "*" }
  ] : [])

  bastion_out_rules = [
    { name = "allow-ssh-rdp-out", priority = 100, source = "*", ports = ["22", "3389"], dest = "VirtualNetwork" },
    { name = "allow-azurecloud-out", priority = 110, source = "*", ports = ["443"], dest = "AzureCloud" },
    { name = "allow-data-plane-out", priority = 120, source = "VirtualNetwork", ports = ["8080", "5701"], dest = "VirtualNetwork" },
    { name = "allow-session-checks-out", priority = 130, source = "*", ports = ["80"], dest = "Internet" },
  ]
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-vnet-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.33.0.0/16"]
  tags                = local.tags
}

# The name must be exactly AzureBastionSubnet and the size /26 or larger.
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.bastion_subnet_prefix]
}

resource "azurerm_network_security_group" "bastion" {
  name                = "${var.name_prefix}-nsg-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.bastion_in_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.dest
    }
  }

  dynamic "security_rule" {
    for_each = local.bastion_out_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.dest
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-vnet-spoke"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.34.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.34.1.0/24"]
}
