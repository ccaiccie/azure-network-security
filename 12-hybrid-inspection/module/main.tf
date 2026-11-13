locals {
  branch_ip = "172.16.10.10"
  spoke_ip  = "10.20.1.20"
  networks = {
    hub        = "10.0.0.0/16"
    branch     = "172.16.0.0/16"
    spoke      = "10.20.0.0/16"
    management = "10.40.0.0/16"
  }
  workloads = {
    branch = { workload = "172.16.10.0/24", ip = "172.16.10.10", bastion = "172.16.250.0/26" }
    spoke  = { workload = "10.20.1.0/24", ip = "10.20.1.20", bastion = "10.40.2.0/26" }
  }
  gateways = { hub = "10.0.254.0/26", branch = "172.16.254.0/26" }
  management = {
    branch = { vnet = "branch", subnet = "172.16.250.0/26" }
    azure  = { vnet = "management", subnet = "10.40.2.0/26" }
  }
  ordinary_peerings = {
    management-to-hub   = { source = "management", target = "hub" }
    hub-to-management   = { source = "hub", target = "management" }
    management-to-spoke = { source = "management", target = "spoke" }
    spoke-to-management = { source = "spoke", target = "management" }
  }
  tags                 = merge(var.tags, { purpose = "disposable-hybrid-inspection-lab", managed_by = "terraform" })
  test_nsg_action      = var.test_paths_enabled ? "Allow" : "Deny"
  test_firewall_action = var.allow_test_flow ? "Allow" : "Deny"
  test_nsg_rules = {
    branch = [
      { name = "test-forward", priority = 100, direction = "Outbound", source = "172.16.10.10/32", destination = "10.20.1.20/32", ports = ["8080", "8081"] },
      { name = "test-reverse-new", priority = 101, direction = "Inbound", source = "10.20.1.20/32", destination = "172.16.10.10/32", ports = ["8082"] }
    ]
    spoke = [
      { name = "test-forward", priority = 100, direction = "Inbound", source = "172.16.10.10/32", destination = "10.20.1.20/32", ports = ["8080", "8081"] },
      { name = "test-reverse-new", priority = 101, direction = "Outbound", source = "10.20.1.20/32", destination = "172.16.10.10/32", ports = ["8082"] }
    ]
  }
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
  address_prefixes                = [each.value.workload]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab["hub"].name
  address_prefixes     = ["10.0.1.0/26"]
  # No route-table/NSG association: preserve gateway propagation and firewall management.
}
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab["hub"].name
  remote_virtual_network_id    = azurerm_virtual_network.lab["spoke"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_gateway.lab]
}
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab["spoke"].name
  remote_virtual_network_id    = azurerm_virtual_network.lab["hub"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true
  depends_on                   = [azurerm_virtual_network_peering.hub_to_spoke]
}
resource "azurerm_virtual_network_peering" "management" {
  for_each                     = local.ordinary_peerings
  name                         = each.key
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab[each.value.source].name
  remote_virtual_network_id    = azurerm_virtual_network.lab[each.value.target].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
