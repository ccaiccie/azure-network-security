# Free network objects: resource group, three VNets, peerings, and the two delegated resolver subnets.
# Nothing in this file bills by the hour. The hub stands for the Azure hub, the "onprem" VNet is a
# stand-in for an on-premises network that you reach over a peering instead of ExpressRoute or a VPN.

locals {
  tags        = merge({ lab = "azure-21-hybrid-dns-resolver", purpose = "study" }, var.tags)
  inbound_ip  = "10.50.0.4" # first usable address in 10.50.0.0/28 (Azure reserves .0 to .3)
  onprem_dns  = "10.60.1.10"
  corp_domain = "corp.example.com."
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- hub (resolver lives here)

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.50.0.0/16"]
  tags                = local.tags
}

# Each endpoint needs its own subnet, delegated to Microsoft.Network/dnsResolvers.
resource "azurerm_subnet" "dns_in" {
  name                 = "snet-dns-in"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.50.0.0/28"]

  delegation {
    name = "dnsresolver"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "dns_out" {
  name                 = "snet-dns-out"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.50.0.16/28"]

  delegation {
    name = "dnsresolver"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.50.2.0/24"]
}

# ---------------------------------------------------------------- spoke

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-spoke"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.51.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.51.1.0/24"]
}

# ---------------------------------------------------------------- simulated on-premises

resource "azurerm_virtual_network" "onprem" {
  name                = "${var.name_prefix}-onprem"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "servers" {
  name                 = "snet-servers"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = ["10.60.1.0/24"]
}

# ---------------------------------------------------------------- peerings (the stand-in for the hybrid link)

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "hub_to_onprem" {
  name                         = "hub-to-onprem"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.onprem.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "onprem_to_hub" {
  name                         = "onprem-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.onprem.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ---------------------------------------------------------------- DNS server settings of the VNets

# Centralized option: the spoke asks the inbound endpoint directly (Activity 3).
resource "azurerm_virtual_network_dns_servers" "spoke" {
  count              = var.spoke_uses_inbound_dns && var.deploy_resolver ? 1 : 0
  virtual_network_id = azurerm_virtual_network.spoke.id
  dns_servers        = [local.inbound_ip]
}

# The simulated on-premises VMs use their own DNS server, as a real site would.
resource "azurerm_virtual_network_dns_servers" "onprem" {
  count              = var.deploy_vms ? 1 : 0
  virtual_network_id = azurerm_virtual_network.onprem.id
  dns_servers        = [local.onprem_dns]
}
