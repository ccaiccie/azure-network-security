locals {
  app_ip     = "10.10.1.10"
  backend_ip = "10.20.1.20"
  spokes = {
    app     = { cidr = "10.10.0.0/16", workload = "10.10.1.0/24", bastion = "10.10.2.0/26", ip = "10.10.1.10" }
    backend = { cidr = "10.20.0.0/16", workload = "10.20.1.0/24", bastion = "10.20.2.0/26", ip = "10.20.1.20" }
  }
  tags                 = merge(var.tags, { purpose = "disposable-vwan-private-inspection-lab", managed_by = "terraform" })
  test_nsg_action      = var.test_paths_enabled ? "Allow" : "Deny"
  test_firewall_action = var.allow_test_flow ? "Allow" : "Deny"
  test_nsg_rules = {
    app = [
      { name = "test-forward", priority = 100, direction = "Outbound", source = "10.10.1.10/32", destination = "10.20.1.20/32", ports = ["8080", "8081"] },
      { name = "test-reverse-new", priority = 101, direction = "Inbound", source = "10.20.1.20/32", destination = "10.10.1.10/32", ports = ["8082"] }
    ]
    backend = [
      { name = "test-forward", priority = 100, direction = "Inbound", source = "10.10.1.10/32", destination = "10.20.1.20/32", ports = ["8080", "8081"] },
      { name = "test-reverse-new", priority = 101, direction = "Outbound", source = "10.20.1.20/32", destination = "10.10.1.10/32", ports = ["8082"] }
    ]
  }
}
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_wan" "lab" {
  name                           = "lab-wan"
  resource_group_name            = azurerm_resource_group.lab.name
  location                       = azurerm_resource_group.lab.location
  type                           = "Standard"
  allow_branch_to_branch_traffic = false
  tags                           = local.tags
}
resource "azurerm_virtual_hub" "lab" {
  name                                   = "secured-hub"
  resource_group_name                    = azurerm_resource_group.lab.name
  location                               = azurerm_resource_group.lab.location
  virtual_wan_id                         = azurerm_virtual_wan.lab.id
  address_prefix                         = "10.0.0.0/23"
  sku                                    = "Standard"
  branch_to_branch_traffic_enabled       = false
  virtual_router_auto_scale_min_capacity = 2
  tags                                   = local.tags
  # No customer hub VNet/subnets, custom hub route table or static routes.
}
resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value.cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "workload" {
  for_each                        = local.spokes
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke[each.key].name
  address_prefixes                = [each.value.workload]
  default_outbound_access_enabled = false
}
resource "azurerm_route_table" "workload" {
  for_each                      = local.spokes
  name                          = "${each.key}-outbound-safety"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = true
  tags                          = local.tags
  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
  # This default discard is NOT the firewall steering mechanism.
}
resource "azurerm_subnet_route_table_association" "workload" {
  for_each       = local.spokes
  subnet_id      = azurerm_subnet.workload[each.key].id
  route_table_id = azurerm_route_table.workload[each.key].id
}
# Explicit serialization. Intent owns all association/propagation; routing omitted.
resource "azurerm_virtual_hub_connection" "app" {
  name                      = "connect-app"
  virtual_hub_id            = azurerm_virtual_hub.lab.id
  remote_virtual_network_id = azurerm_virtual_network.spoke["app"].id
  internet_security_enabled = false
  depends_on                = [azurerm_firewall.lab]
}
resource "azurerm_virtual_hub_connection" "backend" {
  name                      = "connect-backend"
  virtual_hub_id            = azurerm_virtual_hub.lab.id
  remote_virtual_network_id = azurerm_virtual_network.spoke["backend"].id
  internet_security_enabled = false
  depends_on                = [azurerm_virtual_hub_connection.app]
}
resource "azurerm_virtual_hub_routing_intent" "private" {
  name           = "private-inspection"
  virtual_hub_id = azurerm_virtual_hub.lab.id
  routing_policy {
    name         = "PrivateTrafficPolicy"
    destinations = ["PrivateTraffic"]
    next_hop     = azurerm_firewall.lab.id
  }
  depends_on = [azurerm_virtual_hub_connection.backend, azurerm_firewall_policy_rule_collection_group.private]
  # Inverse deletion may remove intent before connections. Isolate workloads first.
}
resource "azurerm_network_security_group" "workload" {
  for_each            = local.spokes
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.test_nsg_rules[each.key]
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = local.test_nsg_action
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = length(security_rule.value.ports) == 1 ? one(security_rule.value.ports) : null
      destination_port_ranges    = length(security_rule.value.ports) > 1 ? security_rule.value.ports : null
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  security_rule {
    name                       = "allow-local-bastion-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = each.value.bastion
    destination_address_prefix = "${each.value.ip}/32"
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
  for_each              = local.spokes
  name                  = "${each.key}-nic"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  ip_forwarding_enabled = false
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    primary                       = true
  }
}
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = local.spokes
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.workload[each.key].id
}
