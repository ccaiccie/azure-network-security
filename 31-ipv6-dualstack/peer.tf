# Gate 4: a second dual-stack VNet, peered with the main VNet in both directions. No VMs: the effective routes of
# vm-web-1 show the peer's IPv4 and IPv6 prefixes with next hop type VNetPeering.

resource "azurerm_virtual_network" "peer" {
  count               = var.deploy_peer ? 1 : 0
  name                = "${local.p}-vnet-peer"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.peer_ipv4_prefix, var.peer_ipv6_prefix]
  tags                = local.tags
}

resource "azurerm_subnet" "peer" {
  count                           = var.deploy_peer ? 1 : 0
  name                            = "snet-peer"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.peer[0].name
  address_prefixes                = ["10.32.1.0/24", cidrsubnet(var.peer_ipv6_prefix, 16, 1)]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network_peering" "main_to_peer" {
  count                     = var.deploy_peer ? 1 : 0
  name                      = "main-to-peer"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.main.name
  remote_virtual_network_id = azurerm_virtual_network.peer[0].id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "peer_to_main" {
  count                     = var.deploy_peer ? 1 : 0
  name                      = "peer-to-main"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.peer[0].name
  remote_virtual_network_id = azurerm_virtual_network.main.id
  allow_forwarded_traffic   = true
}
