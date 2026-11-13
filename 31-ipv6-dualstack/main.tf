# Free baseline: a dual-stack VNet, two dual-stack subnets, an NSG, an empty route table and a private DNS zone.
# Address plan (examples): IPv4 from RFC 1918, IPv6 from the documentation prefix 2001:db8::/32 (RFC 3849).
#   vnet        10.31.0.0/16   + 2001:db8:31::/48
#   snet-web    10.31.1.0/24   + 2001:db8:31:1::/64
#   snet-client 10.31.2.0/24   + 2001:db8:31:2::/64

locals {
  tags = merge({ lab = "ds31-ipv6-dualstack", purpose = "course-lab" }, var.tags)
  p    = var.name_prefix

  web_v4    = "10.31.1.0/24"
  client_v4 = "10.31.2.0/24"
  web_v6    = cidrsubnet(var.ipv6_vnet_prefix, 16, 1)
  client_v6 = cidrsubnet(var.ipv6_vnet_prefix, 16, 2)
}

resource "azurerm_resource_group" "lab" {
  name     = "${local.p}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.p}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.ipv4_vnet_prefix, var.ipv6_vnet_prefix]
  tags                = local.tags
}

# Each subnet carries one IPv4 and one IPv6 prefix. IPv6 subnets are /64.
resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [local.web_v4, local.web_v6]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "client" {
  name                            = "snet-client"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [local.client_v4, local.client_v6]
  default_outbound_access_enabled = false
}

# NSG: IPv4 and IPv6 are matched by separate rules. The IPv6 rule is the one break_fix = nsg_v4_only removes.
resource "azurerm_network_security_group" "app" {
  name                = "${local.p}-nsg-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-app-v4-in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.break_fix == "nsg_v4_only" ? [] : [1]
    content {
      name                       = "allow-app-v6-in"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8080"
      source_address_prefix      = "::/0"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "client" {
  subnet_id                 = azurerm_subnet.client.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# Route table on snet-client. Empty unless break_fix = udr_v4_only, which adds an IPv4-only default route to an
# address where no appliance exists. There is deliberately no IPv6 route, so IPv6 keeps the system route.
resource "azurerm_route_table" "client" {
  name                = "${local.p}-rt-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_route" "v4_default_to_nowhere" {
  count                  = var.break_fix == "udr_v4_only" ? 1 : 0
  name                   = "v4-default-to-appliance"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.client.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.31.9.4"
}

resource "azurerm_subnet_route_table_association" "client" {
  subnet_id      = azurerm_subnet.client.id
  route_table_id = azurerm_route_table.client.id
}

# Private DNS zone with a link to the VNet. The A and AAAA records are created with the VMs (gate 1).
resource "azurerm_private_dns_zone" "lab" {
  name                = "ds31.internal"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "lab" {
  name                  = "link-main"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.lab.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}
