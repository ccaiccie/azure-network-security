locals {
  hub_cidr           = "10.0.0.0/16"
  rs_cidr            = "10.0.1.0/26"
  nva_cidr           = "10.0.2.0/24"
  bastion_cidr       = "10.0.3.0/26"
  app_ip             = "10.10.1.10"
  remote_ip          = "10.30.1.20"
  destination_ip     = "172.20.50.10"
  destination_prefix = "172.20.50.0/24"
  nvas               = { nva1 = "10.0.2.4", nva2 = "10.0.2.5" }
  private_ips        = merge({ app = local.app_ip, remote = local.remote_ip }, local.nvas)
  spokes = {
    app    = { cidr = "10.10.0.0/16", subnet = "10.10.1.0/24", propagation = true }
    remote = { cidr = "10.30.0.0/16", subnet = "10.30.1.0/24", propagation = false }
  }
  tags        = merge(var.tags, { purpose = "disposable-routeserver-gre-lab", managed_by = "terraform" })
  rs_peer_ips = sort(tolist(azurerm_route_server.lab.virtual_router_ips))
  rs_asn      = azurerm_route_server.lab.virtual_router_asn
  nsg_service_rules = {
    app = [{ name = "allow-synthetic-tests", direction = "Outbound", priority = 100, protocol = "Tcp", source = "${local.app_ip}/32", destination = "${local.destination_ip}/32", source_ports = ["*"], destination_ports = ["8080", "8081"] }]
    remote = flatten([for name, ip in local.nvas : [
      { name = "outer-from-${name}", direction = "Inbound", priority = name == "nva1" ? 130 : 131, protocol = "*", source = "${ip}/32", destination = "${local.remote_ip}/32", source_ports = ["*"], destination_ports = ["*"] },
      { name = "outer-to-${name}", direction = "Outbound", priority = name == "nva1" ? 130 : 131, protocol = "*", source = "${local.remote_ip}/32", destination = "${ip}/32", source_ports = ["*"], destination_ports = ["*"] }
    ]])
    nva1 = [
      { name = "allow-original-test", direction = "Inbound", priority = 100, protocol = "Tcp", source = "${local.app_ip}/32", destination = "${local.destination_ip}/32", source_ports = ["*"], destination_ports = ["8080", "8081"] },
      { name = "allow-restored-reply", direction = "Outbound", priority = 101, protocol = "Tcp", source = "${local.destination_ip}/32", destination = "${local.app_ip}/32", source_ports = ["8080"], destination_ports = ["*"] },
      { name = "outer-from-remote", direction = "Inbound", priority = 130, protocol = "*", source = "${local.remote_ip}/32", destination = "10.0.2.4/32", source_ports = ["*"], destination_ports = ["*"] },
      { name = "outer-to-remote", direction = "Outbound", priority = 130, protocol = "*", source = "10.0.2.4/32", destination = "${local.remote_ip}/32", source_ports = ["*"], destination_ports = ["*"] }
    ]
    nva2 = [
      { name = "allow-original-test", direction = "Inbound", priority = 100, protocol = "Tcp", source = "${local.app_ip}/32", destination = "${local.destination_ip}/32", source_ports = ["*"], destination_ports = ["8080", "8081"] },
      { name = "allow-restored-reply", direction = "Outbound", priority = 101, protocol = "Tcp", source = "${local.destination_ip}/32", destination = "${local.app_ip}/32", source_ports = ["8080"], destination_ports = ["*"] },
      { name = "outer-from-remote", direction = "Inbound", priority = 130, protocol = "*", source = "${local.remote_ip}/32", destination = "10.0.2.5/32", source_ports = ["*"], destination_ports = ["*"] },
      { name = "outer-to-remote", direction = "Outbound", priority = 130, protocol = "*", source = "10.0.2.5/32", destination = "${local.remote_ip}/32", source_ports = ["*"], destination_ports = ["*"] }
    ]
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
resource "azurerm_subnet" "routeserver" {
  name                 = "RouteServerSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.rs_cidr]
  # Intentionally NO NSG, NO route-table association and no workload setting.
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
resource "azurerm_route_table" "spoke" {
  for_each                      = local.spokes
  name                          = "${each.key}-routes"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = each.value.propagation
  tags                          = local.tags
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
  # No exact synthetic /24 UDR: A must actually learn the BGP route.
}
resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spokes
  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke[each.key].id
}
resource "azurerm_route_table" "nva" {
  name                          = "nva-substrate"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}
resource "azurerm_subnet_route_table_association" "nva" {
  subnet_id      = azurerm_subnet.nva.id
  route_table_id = azurerm_route_table.nva.id
}
# Serialized peering creation, app gateway use only after Route Server exists.
resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke["app"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
  depends_on                   = [azurerm_route_server.lab]
}
resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke["app"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true
  depends_on                   = [azurerm_route_server.lab, azurerm_virtual_network_peering.hub_to_app]
}
resource "azurerm_virtual_network_peering" "hub_to_remote" {
  name                         = "hub-to-remote"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke["remote"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.app_to_hub]
}
resource "azurerm_virtual_network_peering" "remote_to_hub" {
  name                         = "remote-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke["remote"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_remote]
}
resource "azurerm_network_security_group" "vm" {
  for_each            = local.private_ips
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.nsg_service_rules[each.key]
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = length(security_rule.value.source_ports) == 1 ? one(security_rule.value.source_ports) : null
      source_port_ranges         = length(security_rule.value.source_ports) > 1 ? security_rule.value.source_ports : null
      destination_port_range     = length(security_rule.value.destination_ports) == 1 ? one(security_rule.value.destination_ports) : null
      destination_port_ranges    = length(security_rule.value.destination_ports) > 1 ? security_rule.value.destination_ports : null
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  # GRE cannot be expressed by the provider enum here. Above outer rules are '*'
  # scoped to exact real NIC pairs; owned guest rules restrict actual protocol47.
  dynamic "security_rule" {
    for_each = contains(keys(local.nvas), each.key) ? toset(["Inbound", "Outbound"]) : toset([])
    content {
      name                         = "allow-rs-bgp-${lower(security_rule.value)}"
      priority                     = 120
      direction                    = security_rule.value
      access                       = "Allow"
      protocol                     = "Tcp"
      source_port_range            = "*"
      destination_port_range       = "179"
      source_address_prefix        = security_rule.value == "Outbound" ? "${each.value}/32" : null
      source_address_prefixes      = security_rule.value == "Inbound" ? [for ip in local.rs_peer_ips : "${ip}/32"] : null
      destination_address_prefix   = security_rule.value == "Inbound" ? "${each.value}/32" : null
      destination_address_prefixes = security_rule.value == "Outbound" ? [for ip in local.rs_peer_ips : "${ip}/32"] : null
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
  security_rule {
    name                       = "deny-platform-dns"
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
