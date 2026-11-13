# Free network objects: resource group, two VNets with peering, the stand-in NSG and a private DNS zone.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-30-aks-networking", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- AKS VNet
resource "azurerm_virtual_network" "aks" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.node_subnet_cidr]
}

resource "azurerm_subnet" "nodes2" {
  name                 = "snet-nodes2"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = ["10.40.2.0/24"]
}

# ---------------------------------------------------------------- on-premises stand-in VNet
resource "azurerm_virtual_network" "onprem" {
  name                = "${var.name_prefix}-onprem"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.50.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "onprem" {
  name                 = "snet-onprem"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = ["10.50.1.0/24"]
}

resource "azurerm_virtual_network_peering" "aks_to_onprem" {
  name                         = "aks-to-onprem"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.aks.name
  remote_virtual_network_id    = azurerm_virtual_network.onprem.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "onprem_to_aks" {
  name                         = "onprem-to-aks"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.onprem.name
  remote_virtual_network_id    = azurerm_virtual_network.aks.id
  allow_virtual_network_access = true
}

# ---------------------------------------------------------------- NSG of the stand-in subnet
# Rule 200 is an explicit deny above the default AllowVnetInBound: the VirtualNetwork tag
# also covers peered address space, so without it the allow list would have no effect.
resource "azurerm_network_security_group" "onprem" {
  name                = "nsg-onprem"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-8080-from-list"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = var.onprem_allowed_source
    destination_address_prefix = "10.50.1.0/24"
  }

  security_rule {
    name                       = "deny-8080-other"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "10.50.1.0/24"
  }
}

resource "azurerm_subnet_network_security_group_association" "onprem" {
  subnet_id                 = azurerm_subnet.onprem.id
  network_security_group_id = azurerm_network_security_group.onprem.id
}

# ---------------------------------------------------------------- private DNS zone
resource "azurerm_private_dns_zone" "lab" {
  name                = "lab30.internal"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_dns_a_record" "db" {
  name                = "db"
  zone_name           = azurerm_private_dns_zone.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 60
  records             = ["10.50.1.4"]
}

# Break/fix case 4: with link_private_zone = false the zone exists but the AKS VNet cannot see it.
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.link_private_zone ? 1 : 0
  name                  = "link-aks"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.lab.name
  virtual_network_id    = azurerm_virtual_network.aks.id
  registration_enabled  = false
}
