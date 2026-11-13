locals {
  app_ip            = "10.20.1.10"
  perimeter_ip      = "10.30.1.4"
  origin_ip         = "10.50.1.20"
  management_prefix = "10.40.2.0/26"
  networks          = { hub = "10.0.0.0/16", app = "10.20.0.0/16", perimeter = "10.30.0.0/16", origin = "10.50.0.0/16", management = "10.40.0.0/16" }
  workloads = {
    app       = { prefix = "10.20.1.0/24", ip = "10.20.1.10" }
    perimeter = { prefix = "10.30.1.0/24", ip = "10.30.1.4" }
    origin    = { prefix = "10.50.1.0/24", ip = "10.50.1.20" }
  }
  transit_peerings = {
    hub-to-app       = { source = "hub", target = "app" }
    app-to-hub       = { source = "app", target = "hub" }
    hub-to-perimeter = { source = "hub", target = "perimeter" }
    perimeter-to-hub = { source = "perimeter", target = "hub" }
  }
  tags                 = merge(var.tags, { purpose = "disposable-peered-perimeter-simulator", managed_by = "terraform" })
  source_prefix        = var.source_mode == "preserve" ? "10.20.1.10/32" : "10.0.1.0/26"
  test_nsg_action      = var.test_paths_enabled ? "Allow" : "Deny"
  origin_nsg_action    = var.origin_access_enabled ? "Allow" : "Deny"
  test_firewall_action = var.allow_test_flow ? "Allow" : "Deny"
}
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "lab" {
  for_each            = local.networks
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value]
  tags                = local.tags
}
resource "azurerm_subnet" "workload" {
  for_each                        = local.workloads
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab[each.key].name
  address_prefixes                = [each.value.prefix]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab["hub"].name
  address_prefixes     = ["10.0.1.0/26"]
}
resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab["hub"].name
  address_prefixes     = ["10.0.2.0/26"]
  # Service-managed Internet default and disabled propagation. No customer table/NSG.
}
resource "azurerm_virtual_network_peering" "transit" {
  for_each                     = local.transit_peerings
  name                         = each.key
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab[each.value.source].name
  remote_virtual_network_id    = azurerm_virtual_network.lab[each.value.target].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_virtual_network_peering" "management_to_target" {
  for_each                     = toset(["hub", "app", "perimeter", "origin"])
  name                         = "management-to-${each.key}"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab["management"].name
  remote_virtual_network_id    = azurerm_virtual_network.lab[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_virtual_network_peering" "target_to_management" {
  for_each                     = toset(["hub", "app", "perimeter", "origin"])
  name                         = "${each.key}-to-management"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.lab["management"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_public_ip" "endpoint" {
  for_each            = toset(["perimeter", "origin"])
  name                = "${each.key}-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
