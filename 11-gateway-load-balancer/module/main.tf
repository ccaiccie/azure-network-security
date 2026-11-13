locals {
  tags              = { purpose = "gwlb-stateless-teaching", owner = "operator", no_runtime_validation = "true" }
  networks          = { provider = "10.0.0.0/16", consumer = "10.20.0.0/16", management = "10.40.0.0/16" }
  nodes             = { nva1 = { ip = "10.0.1.4", network = "provider" }, nva2 = { ip = "10.0.1.5", network = "provider" }, app = { ip = "10.20.1.20", network = "consumer" } }
  gwlb_ip           = "10.0.2.10"
  backend_ip        = "10.20.1.20"
  management_prefix = "10.40.2.0/26"
  test_nsg_action   = var.test_paths_enabled ? "Allow" : "Deny"
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
  for_each                        = { provider = "10.0.1.0/24", consumer = "10.20.1.0/24" }
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab[each.key].name
  address_prefixes                = [each.value]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "frontend" {
  name                            = "gwlb-frontend"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab["provider"].name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
}
resource "azurerm_virtual_network_peering" "management_to_target" {
  for_each                     = toset(["provider", "consumer"])
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
  for_each                     = toset(["provider", "consumer"])
  name                         = "${each.key}-to-management"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.lab["management"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
# No provider-consumer peering, gateway, NAT, inspection UDR, or 0/0 None route.
resource "azurerm_network_interface" "vm" {
  for_each              = local.nodes
  name                  = "${each.key}-nic"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  ip_forwarding_enabled = each.key != "app"
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload[each.value.network].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}
