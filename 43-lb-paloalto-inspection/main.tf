# Free baseline: resource group, hub and app VNets, subnets, the peering, NSGs and one route table with no routes.
# The user routes live in routes.tf because they need the internal load balancer.

locals {
  tags = merge({ lab = "cs43-lb-paloalto", managed_by = "terraform" }, var.tags)
  p    = var.name_prefix
}

resource "azurerm_resource_group" "lab" {
  name     = "${local.p}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- hub

resource "azurerm_virtual_network" "hub" {
  name                = "${local.p}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.80.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.0.0/24"]
}

resource "azurerm_subnet" "untrust" {
  name                 = "snet-untrust"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.1.0/24"]
}

resource "azurerm_subnet" "trust" {
  name                 = "snet-trust"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.2.0/24"]
}

resource "azurerm_subnet" "gwlb" {
  name                 = "snet-gwlb"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.80.3.0/24"]
}

# ---------------------------------------------------------------- app spoke

resource "azurerm_virtual_network" "app" {
  name                = "${local.p}-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.81.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.81.0.0/24"]
}

# ---------------------------------------------------------------- peering (forwarded traffic on both sides, no gateway)

resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.app.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.app.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ---------------------------------------------------------------- NSGs

resource "azurerm_network_security_group" "mgmt" {
  name                = "${local.p}-nsg-mgmt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-mgmt-from-operator"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "22"]
    source_address_prefix      = var.mgmt_source_cidr
    destination_address_prefix = "*"
  }
}

# A Standard public IP and load balancer accept nothing until an NSG allows it. The probe rule names the service tag
# AzureLoadBalancer (source 168.63.129.16). The default AllowAzureLoadBalancerInBound rule also covers it; the explicit
# rule documents the dependency and is what the break/fix cases act on.
resource "azurerm_network_security_group" "untrust" {
  name                = "${local.p}-nsg-untrust"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.probe_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_rule" "allow_http_in" {
  count                       = var.nsg_allow_http_inbound ? 1 : 0
  name                        = "allow-http-in"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.untrust.name
}

# Break/fix case 1: a deny for the load balancer tag with a lower number than the allow.
resource "azurerm_network_security_rule" "break_probe" {
  count                       = var.break_probe_block ? 1 : 0
  name                        = "deny-lb-probe-break"
  priority                    = 90
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.untrust.name
}

resource "azurerm_network_security_group" "trust" {
  name                = "${local.p}-nsg-trust"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.probe_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "gwlb" {
  name                = "${local.p}-nsg-gwlb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.probe_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vxlan-from-vnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = ["10800", "10801"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# The web subnet keeps the default rules: the firewall's trust address and the probes are inside the virtual network
# range. The rule below admits the Internet only for the Gateway LB variant, where clients reach the web VMs through
# the chained public frontend.
resource "azurerm_network_security_group" "web" {
  name                = "${local.p}-nsg-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "web_http_from_internet" {
  count                       = var.deploy_gateway_lb ? 1 : 0
  name                        = "allow-http-gwlb-variant"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "untrust" {
  subnet_id                 = azurerm_subnet.untrust.id
  network_security_group_id = azurerm_network_security_group.untrust.id
}

resource "azurerm_subnet_network_security_group_association" "trust" {
  subnet_id                 = azurerm_subnet.trust.id
  network_security_group_id = azurerm_network_security_group.trust.id
}

resource "azurerm_subnet_network_security_group_association" "gwlb" {
  subnet_id                 = azurerm_subnet.gwlb.id
  network_security_group_id = azurerm_network_security_group.gwlb.id
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# ---------------------------------------------------------------- route table for the web subnet (routes are in routes.tf)

resource "azurerm_route_table" "web" {
  name                          = "${local.p}-rt-web"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags
}

resource "azurerm_subnet_route_table_association" "web" {
  subnet_id      = azurerm_subnet.web.id
  route_table_id = azurerm_route_table.web.id
}
