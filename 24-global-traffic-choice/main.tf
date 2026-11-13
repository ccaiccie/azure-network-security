# Free network objects: resource group, one VNet, two subnets, two NSGs.
# Nothing in this file bills by the hour.

locals {
  tags = merge({ lab = "azure-24-global-traffic-choice", purpose = "study" }, var.tags)

  web_ips = ["10.24.2.11", "10.24.2.12"]
  # Prefix lists for the NSG rules. The Front Door and Traffic Manager source tags are service tags.
  appgw_sources = var.appgw_only_from_front_door ? ["AzureFrontDoor.Backend", "AzureTrafficManager"] : [var.my_ip_cidr, "AzureFrontDoor.Backend", "AzureTrafficManager"]
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.24.0.0/16"]
  tags                = local.tags
}

# The Application Gateway needs a subnet of its own.
resource "azurerm_subnet" "agw" {
  name                 = "snet-agw"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.24.1.0/24"]
}

# The web VMs have no public IPs and no default outbound access; the load balancer rule gives them outbound SNAT.
resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.24.2.0/24"]
  default_outbound_access_enabled = false
}

# Application Gateway v2 subnet NSG: the GatewayManager range is mandatory; the other rules decide who may browse.
resource "azurerm_network_security_group" "agw" {
  name                = "${var.name_prefix}-nsg-agw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-gatewaymanager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-azurelb"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-clients"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = local.appgw_sources
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  subnet_id                 = azurerm_subnet.agw.id
  network_security_group_id = azurerm_network_security_group.agw.id
}

# Web subnet NSG: the load balancer path reaches the VMs with the client's own address, so your address must be allowed.
resource "azurerm_network_security_group" "web" {
  name                = "${var.name_prefix}-nsg-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http-from-me-and-probes"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = [var.my_ip_cidr, "AzureTrafficManager"]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-from-agw-subnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.24.1.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}
