locals {
  endpoint_ip       = "10.30.1.7"
  management_prefix = "10.40.2.0/26"
  networks          = { hub = "10.0.0.0/16", client = "10.10.0.0/16", endpoint = "10.30.0.0/16", management = "10.40.0.0/16" }
  clients           = { reader = "10.10.1.10", seed = "10.10.1.11" }
  peerings = {
    hub-to-client        = { source = "hub", target = "client", forwarded = true }
    client-to-hub        = { source = "client", target = "hub", forwarded = true }
    hub-to-endpoint      = { source = "hub", target = "endpoint", forwarded = true }
    endpoint-to-hub      = { source = "endpoint", target = "hub", forwarded = true }
    client-to-endpoint   = { source = "client", target = "endpoint", forwarded = false }
    endpoint-to-client   = { source = "endpoint", target = "client", forwarded = false }
    management-to-client = { source = "management", target = "client", forwarded = false }
    client-to-management = { source = "client", target = "management", forwarded = false }
  }
  tags           = merge(var.tags, { purpose = "disposable-private-endpoint-inspection", managed_by = "terraform" })
  client_actions = { reader = var.client_paths_enabled ? "Allow" : "Deny", seed = var.seed_paths_enabled ? "Allow" : "Deny" }
  app_actions    = { reader = var.allow_client_blob ? "Allow" : "Deny", seed = var.allow_seed_blob ? "Allow" : "Deny" }
  dns_action     = var.dns_enabled ? "Allow" : "Deny"
  blob_fqdn      = "${var.storage_account_name}.blob.core.windows.net"
  container_name = "lab-data"
  blob_name      = "proof.txt"
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
resource "azurerm_subnet" "client" {
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab["client"].name
  address_prefixes                = ["10.10.1.0/24"]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "endpoint" {
  name                              = "private-endpoints"
  resource_group_name               = azurerm_resource_group.lab.name
  virtual_network_name              = azurerm_virtual_network.lab["endpoint"].name
  address_prefixes                  = ["10.30.1.0/24"]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = var.pe_network_policies
}
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab["hub"].name
  address_prefixes     = ["10.0.1.0/26"]
}
resource "azurerm_virtual_network_peering" "lab" {
  for_each                     = local.peerings
  name                         = each.key
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.lab[each.value.source].name
  remote_virtual_network_id    = azurerm_virtual_network.lab[each.value.target].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = each.value.forwarded
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
