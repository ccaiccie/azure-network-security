locals {
  hub_cidr     = "10.0.0.0/16"
  nva_cidr     = "10.0.2.0/24"
  bastion_cidr = "10.0.3.0/26"
  frontend_ip  = "10.0.2.10"
  app_ip       = "10.10.1.10"
  backend_ip   = "10.20.1.20"
  tags         = merge(var.tags, { purpose = "disposable-linux-nva-lab", managed_by = "terraform" })
  spokes = {
    app     = { cidr = "10.10.0.0/16", subnet = "10.10.1.0/24", remote = "10.20.0.0/16" }
    backend = { cidr = "10.20.0.0/16", subnet = "10.20.1.0/24", remote = "10.10.0.0/16" }
  }
  nvas            = { nva1 = "10.0.2.4", nva2 = "10.0.2.5" }
  private_ips     = merge({ app = local.app_ip, backend = local.backend_ip }, local.nvas)
  transit_forward = { source = "${local.app_ip}/32", destination = "${local.backend_ip}/32", source_ports = ["*"], destination_ports = ["8080", "8081"] }
  transit_reply   = { source = "${local.backend_ip}/32", destination = "${local.app_ip}/32", source_ports = ["8080", "8081"], destination_ports = ["*"] }
  service_rules = {
    app     = [merge(local.transit_forward, { name = "allow-backend-tests", direction = "Outbound", priority = 100 })]
    backend = [merge(local.transit_forward, { name = "allow-app-tests", direction = "Inbound", priority = 100 })]
    nva1 = [for r in [
      { name = "transit-forward-in", direction = "Inbound", priority = 100, reverse = false },
      { name = "transit-reply-in", direction = "Inbound", priority = 101, reverse = true },
      { name = "transit-forward-out", direction = "Outbound", priority = 100, reverse = false },
      { name = "transit-reply-out", direction = "Outbound", priority = 101, reverse = true }
    ] : merge(r.reverse ? local.transit_reply : local.transit_forward, r)]
    nva2 = [for r in [
      { name = "transit-forward-in", direction = "Inbound", priority = 100, reverse = false },
      { name = "transit-reply-in", direction = "Inbound", priority = 101, reverse = true },
      { name = "transit-forward-out", direction = "Outbound", priority = 100, reverse = false },
      { name = "transit-reply-out", direction = "Outbound", priority = 101, reverse = true }
    ] : merge(r.reverse ? local.transit_reply : local.transit_forward, r)]
  }
}
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "hub" {
  name                = "hub"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [local.hub_cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "nva" {
  name                            = "nva"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [local.nva_cidr]
  default_outbound_access_enabled = false
}
resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value.cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "spoke" {
  for_each                        = local.spokes
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke[each.key].name
  address_prefixes                = [each.value.subnet]
  default_outbound_access_enabled = false
}
# Explicitly serialize peering operations. There is no app-to-backend direct peering.
resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke["app"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke["app"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_app]
}

resource "azurerm_virtual_network_peering" "hub_to_backend" {
  name                         = "hub-to-backend"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke["backend"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.app_to_hub]
}

resource "azurerm_virtual_network_peering" "backend_to_hub" {
  name                         = "backend-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke["backend"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_backend]
}

resource "azurerm_route_table" "spoke" {
  for_each                      = local.spokes
  name                          = "${each.key}-inspect"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "remote-spoke"
    address_prefix         = each.value.remote
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.frontend_ip
  }
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}
resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spokes
  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke[each.key].id
}
resource "azurerm_route_table" "nva" {
  name                          = "nva-block-internet"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
  # No remote-prefix UDR back to F: NVAs use hub/spoke system peering routes.
}
resource "azurerm_subnet_route_table_association" "nva" {
  subnet_id      = azurerm_subnet.nva.id
  route_table_id = azurerm_route_table.nva.id
}
resource "azurerm_network_security_group" "vm" {
  for_each            = local.private_ips
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.service_rules[each.key]
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = length(security_rule.value.source_ports) == 1 ? one(security_rule.value.source_ports) : null
      source_port_ranges         = length(security_rule.value.source_ports) > 1 ? security_rule.value.source_ports : null
      destination_port_range     = length(security_rule.value.destination_ports) == 1 ? one(security_rule.value.destination_ports) : null
      destination_port_ranges    = length(security_rule.value.destination_ports) > 1 ? security_rule.value.destination_ports : null
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  security_rule {
    name                       = "allow-bastion-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bastion_cidr
    destination_address_prefix = "${each.value}/32"
  }
  dynamic "security_rule" {
    for_each = contains(keys(local.nvas), each.key) ? [1] : []
    content {
      name                       = "allow-lb-health"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8008"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "${each.value}/32"
    }
  }
  security_rule {
    name                       = "deny-direct-platform-dns"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzurePlatformDNS"
  }
  dynamic "security_rule" {
    for_each = toset(["Inbound", "Outbound"])
    content {
      name                       = "deny-other-${lower(security_rule.key)}"
      priority                   = 4000
      direction                  = security_rule.key
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}
resource "azurerm_network_interface" "vm" {
  for_each              = local.private_ips
  name                  = "${each.key}-nic"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  ip_forwarding_enabled = contains(keys(local.nvas), each.key)
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = contains(keys(local.nvas), each.key) ? azurerm_subnet.nva.id : azurerm_subnet.spoke[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value
    primary                       = true
  }
}
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = local.private_ips
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.vm[each.key].id
}
