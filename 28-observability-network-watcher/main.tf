# Free baseline: a resource group, three VNets (client, server, hub), the peerings and an NSG. Nothing here bills by the hour.
# client 10.80.0.0/24, server 10.81.0.0/24, hub 10.82.0.0/24 (the hub only matters with the firewall gate).
# Example private addresses (RFC 1918).

locals {
  tags = merge({ lab = "azure-28-network-watcher", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "client" {
  name                = "${var.name_prefix}-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.80.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "client" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.client.name
  address_prefixes     = ["10.80.0.0/26"]
}

resource "azurerm_virtual_network" "server" {
  name                = "${var.name_prefix}-server"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.81.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "server" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.server.name
  address_prefixes     = ["10.81.0.0/26"]
}

# The server subnet NSG. Rule 100 is the switch for break/fix 1: ICMP is always allowed by AllowVnetInBound (65000).
resource "azurerm_network_security_group" "server" {
  name                = "${var.name_prefix}-nsg-server"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "app-port"
    priority                   = 100
    direction                  = "Inbound"
    access                     = var.nsg_allows_app_port ? "Allow" : "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.app_port)
    source_address_prefix      = "10.80.0.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "server" {
  subnet_id                 = azurerm_subnet.server.id
  network_security_group_id = azurerm_network_security_group.server.id
}

# Direct peering between client and server (both directions are needed).
resource "azurerm_virtual_network_peering" "client_to_server" {
  name                      = "client-to-server"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.client.name
  remote_virtual_network_id = azurerm_virtual_network.server.id
}

resource "azurerm_virtual_network_peering" "server_to_client" {
  name                      = "server-to-client"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.server.name
  remote_virtual_network_id = azurerm_virtual_network.client.id
}

# The regional Network Watcher. Azure normally creates one per region in NetworkWatcherRG when a VNet is created.
data "azurerm_network_watcher" "this" {
  count               = var.create_network_watcher ? 0 : 1
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

resource "azurerm_network_watcher" "this" {
  count               = var.create_network_watcher ? 1 : 0
  name                = "NetworkWatcher_${var.location}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

locals {
  watcher_id   = var.create_network_watcher ? azurerm_network_watcher.this[0].id : data.azurerm_network_watcher.this[0].id
  watcher_name = var.create_network_watcher ? azurerm_network_watcher.this[0].name : data.azurerm_network_watcher.this[0].name
  watcher_rg   = var.create_network_watcher ? azurerm_network_watcher.this[0].resource_group_name : data.azurerm_network_watcher.this[0].resource_group_name
}
