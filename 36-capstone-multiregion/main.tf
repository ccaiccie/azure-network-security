# REFERENCE SKELETON: two small hubs and their spokes. Not a full deployment.
# Region A uses 10.20.0.0/15 and region B uses 10.22.0.0/15. Every object sits behind a gate.

locals {
  tags = merge({ course = "azure-capstone-36", status = "reference-skeleton" }, var.tags)

  region_defs = {
    a = {
      location = var.location_a
      block    = "10.20.0.0/15"
      hub      = "10.20.0.0/22"
      fw_ip    = "10.20.0.4"
      peer_fw  = "10.22.0.4"
      peer_blk = "10.22.0.0/15"
      subnets = {
        AzureFirewallSubnet = "10.20.0.0/26"
        GatewaySubnet       = "10.20.0.128/27"
        AzureBastionSubnet  = "10.20.0.192/26"
        snet-dns-in         = "10.20.1.0/28"
        snet-dns-out        = "10.20.1.16/28"
        snet-mgmt           = "10.20.1.64/26"
      }
      spokes = {
        web  = { cidr = "10.20.4.0/22", subnets = { snet-agw = "10.20.4.0/24", snet-web = "10.20.5.0/24" } }
        data = { cidr = "10.20.8.0/22", subnets = { snet-app = "10.20.8.0/24", snet-pe = "10.20.9.0/24" } }
        aks  = { cidr = "10.20.16.0/21", subnets = { snet-aks-nodes = "10.20.16.0/22", snet-aks-pe = "10.20.20.0/24" } }
      }
    }
    b = {
      location = var.location_b
      block    = "10.22.0.0/15"
      hub      = "10.22.0.0/22"
      fw_ip    = "10.22.0.4"
      peer_fw  = "10.20.0.4"
      peer_blk = "10.20.0.0/15"
      subnets = {
        AzureFirewallSubnet = "10.22.0.0/26"
        GatewaySubnet       = "10.22.0.128/27"
        AzureBastionSubnet  = "10.22.0.192/26"
        snet-dns-in         = "10.22.1.0/28"
        snet-dns-out        = "10.22.1.16/28"
        snet-mgmt           = "10.22.1.64/26"
      }
      spokes = {
        web  = { cidr = "10.22.4.0/22", subnets = { snet-agw = "10.22.4.0/24", snet-web = "10.22.5.0/24" } }
        data = { cidr = "10.22.8.0/22", subnets = { snet-app = "10.22.8.0/24", snet-pe = "10.22.9.0/24" } }
        aks  = { cidr = "10.22.16.0/21", subnets = { snet-aks-nodes = "10.22.16.0/22", snet-aks-pe = "10.22.20.0/24" } }
      }
    }
  }

  # Only the regions whose gate is open.
  regions = { for k, r in local.region_defs : k => r if(k == "a" ? var.deploy_region_a : var.deploy_region_b) }

  # One entry per spoke, for example "a-web".
  spokes = merge([
    for rk, r in local.regions : {
      for sk, s in r.spokes : "${rk}-${sk}" => merge(s, { region = rk, name = sk, location = r.location, fw_ip = r.fw_ip, hub = r.hub })
    }
  ]...)

  # One entry per spoke subnet, for example "a-web/snet-web".
  spoke_subnets = merge([
    for sk, s in local.spokes : {
      for name, cidr in s.subnets : "${sk}/${name}" => { spoke = sk, name = name, cidr = cidr }
    }
  ]...)

  hub_subnets = merge([
    for rk, r in local.regions : {
      for name, cidr in r.subnets : "${rk}/${name}" => { region = rk, name = name, cidr = cidr }
    }
  ]...)

  # Spoke subnets that must send 0.0.0.0/0 to the firewall. The application gateway subnet is NOT one of them.
  spoke_subnets_forced = { for k, s in local.spoke_subnets : k => s if s.name != "snet-agw" && s.name != "snet-pe" }
}

resource "azurerm_resource_group" "region" {
  for_each = local.regions
  name     = "${var.name_prefix}-${each.key}-rg"
  location = each.value.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  for_each            = local.regions
  name                = "${var.name_prefix}-hub-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  address_space       = [each.value.hub]
  tags                = local.tags
}

resource "azurerm_subnet" "hub" {
  for_each             = local.hub_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.region[each.value.region].name
  virtual_network_name = azurerm_virtual_network.hub[each.value.region].name
  address_prefixes     = [each.value.cidr]
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = "${var.name_prefix}-spoke-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.value.region].name
  address_space       = [each.value.cidr]
  # Spokes use the hub firewall as their DNS server (DNS proxy). Until the firewall exists the default Azure DNS applies.
  dns_servers = var.deploy_firewalls ? [each.value.fw_ip] : null
  tags        = local.tags
}

resource "azurerm_subnet" "spoke" {
  for_each             = local.spoke_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.region[local.spokes[each.value.spoke].region].name
  virtual_network_name = azurerm_virtual_network.spoke[each.value.spoke].name
  address_prefixes     = [each.value.cidr]
}

# ---------------------------------------------------------------- route tables (see the guide's route-table design)

# Spoke workload subnets: everything private or default goes to the regional firewall; BGP propagation is OFF
# so that on-premises routes learned through the hub gateway can never bypass the firewall.
resource "azurerm_route_table" "spoke" {
  for_each                      = local.regions
  name                          = "${var.name_prefix}-rt-spoke-${each.key}"
  location                      = each.value.location
  resource_group_name           = azurerm_resource_group.region[each.key].name
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  dynamic "route" {
    for_each = {
      "default"  = "0.0.0.0/0"
      "rfc1918a" = "10.0.0.0/8"
      "rfc1918b" = "172.16.0.0/12"
      "rfc1918c" = "192.168.0.0/16"
    }
    content {
      name                   = route.key
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = each.value.fw_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spoke_subnets_forced
  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke[local.spokes[each.value.spoke].region].id
}

# GatewaySubnet: one route per spoke prefix (never the whole /15 and never the hub prefix) so that
# on-premises to spoke traffic is inspected but traffic to hub services (DNS resolver, Bastion) is not hair-pinned.
resource "azurerm_route_table" "gateway" {
  for_each            = local.regions
  name                = "${var.name_prefix}-rt-gw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  tags                = local.tags

  dynamic "route" {
    for_each = { for k, s in local.spokes : s.name => s.cidr if s.region == each.key }
    content {
      name                   = "to-spoke-${route.key}"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = each.value.fw_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "gateway" {
  for_each       = local.regions
  subnet_id      = azurerm_subnet.hub["${each.key}/GatewaySubnet"].id
  route_table_id = azurerm_route_table.gateway[each.key].id
}

# AzureFirewallSubnet: BGP propagation stays ON (the firewall learns on-premises from the gateway).
# The only UDR sends the OTHER region's block to the other firewall.
resource "azurerm_route_table" "firewall" {
  for_each            = local.regions
  name                = "${var.name_prefix}-rt-fw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  tags                = local.tags

  route {
    name                   = "to-other-region"
    address_prefix         = each.value.peer_blk
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = each.value.peer_fw
  }
}

resource "azurerm_subnet_route_table_association" "firewall" {
  for_each       = local.regions
  subnet_id      = azurerm_subnet.hub["${each.key}/AzureFirewallSubnet"].id
  route_table_id = azurerm_route_table.firewall[each.key].id
}

# Application gateway subnet: NO 0.0.0.0/0 UDR (the v2 SKU needs the default route to the Internet).
# Only the private spokes behind the firewall are listed.
resource "azurerm_route_table" "agw" {
  for_each            = local.regions
  name                = "${var.name_prefix}-rt-agw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  tags                = local.tags

  dynamic "route" {
    for_each = { for k, s in local.spokes : s.name => s.cidr if s.region == each.key && s.name != "web" }
    content {
      name                   = "to-spoke-${route.key}"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = each.value.fw_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "agw" {
  for_each       = local.regions
  subnet_id      = azurerm_subnet.spoke["${each.key}-web/snet-agw"].id
  route_table_id = azurerm_route_table.agw[each.key].id
}

# ---------------------------------------------------------------- NSG for the application gateway subnet

resource "azurerm_network_security_group" "agw" {
  for_each            = local.regions
  name                = "${var.name_prefix}-nsg-agw-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
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
    name                       = "allow-frontdoor-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureFrontDoor.Backend"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  for_each                  = local.regions
  subnet_id                 = azurerm_subnet.spoke["${each.key}-web/snet-agw"].id
  network_security_group_id = azurerm_network_security_group.agw[each.key].id
}
