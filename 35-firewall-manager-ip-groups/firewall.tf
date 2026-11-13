# Gate 1, COSTLY: a hub VNet, a Standard static public IP and ONE Azure Firewall that uses the chosen policy.
# Azure Firewall bills per hour from creation until it is deleted (check current pricing); a Premium policy needs a
# Premium firewall. Needs gate 1 and accept_firewall_cost. Attribute names come from provider documentation
# knowledge: check the azurerm docs for your provider version.

locals {
  fw_policy_ids = {
    "child-a" = azurerm_firewall_policy.child_a.id
    "child-b" = azurerm_firewall_policy.child_b.id
    "parent"  = azurerm_firewall_policy.parent.id
  }
}

resource "azurerm_virtual_network" "hub" {
  count               = local.firewall_on ? 1 : 0
  name                = "${var.name_prefix}-vnet-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.hub_prefix]
  tags                = local.tags
}

# The name must be exactly AzureFirewallSubnet and the size /26 or larger.
resource "azurerm_subnet" "firewall" {
  count                = local.firewall_on ? 1 : 0
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = [local.fw_subnet]
}

resource "azurerm_public_ip" "firewall" {
  count               = local.firewall_on ? 1 : 0
  name                = "${var.name_prefix}-pip-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall" "lab" {
  count               = local.firewall_on ? 1 : 0
  name                = "${var.name_prefix}-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.policy_sku
  firewall_policy_id  = var.associate_policy_to_firewall ? local.fw_policy_ids[var.firewall_policy_choice] : null
  tags                = local.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall[0].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  # The policy and its rule groups should exist before the firewall uses them.
  depends_on = [
    azurerm_firewall_policy_rule_collection_group.parent_app,
    azurerm_firewall_policy_rule_collection_group.child_a,
    azurerm_firewall_policy_rule_collection_group.child_b,
  ]
}
