# Free objects: resource group, five IP groups, the parent policy with three rule collection groups,
# two child policies. Policies, rule collection groups and IP groups have no hourly charge by themselves
# (check current pricing). The firewall, the workspace and the Azure Policy audit are in their own gated files.

locals {
  tags = merge({ lab = "azure-35-firewall-manager-ip-groups", purpose = "study" }, var.tags)

  # Gate 1 needs BOTH switches, so one typo cannot create something expensive.
  firewall_on = var.deploy_firewall && var.accept_firewall_cost
  premium     = var.policy_sku == "Premium"

  # Documentation example ranges (RFC 5737) and private ranges (RFC 1918).
  hub_prefix      = "10.60.0.0/16"
  fw_subnet       = "10.60.250.0/26"
  shared_prefix   = "10.60.8.0/24"
  spoke_a_prefix  = "10.61.0.0/16"
  spoke_b_prefix  = "10.62.0.0/16"
  app_a_subnet    = "10.61.1.0/24"
  app_a_new       = "10.61.2.0/24"
  app_b_subnet    = "10.62.1.0/24"
  blocked_example = "198.51.100.0/24"

  # Break/fix 2: the new subnet is only in the IP group when the switch is off.
  app_a_cidrs = var.ipg_app_a_missing_prefix ? [local.app_a_subnet] : [local.app_a_subnet, local.app_a_new]
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- IP groups (reusable address lists)

resource "azurerm_ip_group" "spokes" {
  name                = "${var.name_prefix}-ipg-spokes"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  cidrs               = [local.spoke_a_prefix, local.spoke_b_prefix]
  tags                = local.tags
}

resource "azurerm_ip_group" "app_a" {
  name                = "${var.name_prefix}-ipg-app-a"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  cidrs               = local.app_a_cidrs
  tags                = local.tags
}

resource "azurerm_ip_group" "app_b" {
  name                = "${var.name_prefix}-ipg-app-b"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  cidrs               = [local.app_b_subnet]
  tags                = local.tags
}

resource "azurerm_ip_group" "shared" {
  name                = "${var.name_prefix}-ipg-shared"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  cidrs               = [local.shared_prefix]
  tags                = local.tags
}

resource "azurerm_ip_group" "blocked" {
  name                = "${var.name_prefix}-ipg-blocked"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  cidrs               = [local.blocked_example]
  tags                = local.tags
}
