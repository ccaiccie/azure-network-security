locals {
  app_ip    = "10.10.1.10"
  origin_ip = "10.30.1.20"
  spokes = {
    app    = { cidr = "10.10.0.0/16", workload = "10.10.1.0/24", bastion = "10.40.2.0/26", ip = "10.10.1.10" }
    origin = { cidr = "10.30.0.0/16", workload = "10.30.1.0/24", bastion = "10.30.2.0/26", ip = "10.30.1.20" }
  }
  tags            = merge(var.tags, { purpose = "disposable-partner-internet-intent-lab", managed_by = "terraform" })
  test_nsg_action = var.test_paths_enabled ? "Allow" : "Deny"
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
  name                                   = "partner-hub"
  resource_group_name                    = azurerm_resource_group.lab.name
  location                               = azurerm_resource_group.lab.location
  virtual_wan_id                         = azurerm_virtual_wan.lab.id
  address_prefix                         = "10.0.0.0/23"
  sku                                    = "Standard"
  branch_to_branch_traffic_enabled       = false
  virtual_router_auto_scale_min_capacity = 2
  tags                                   = local.tags
  # External publisher installs the compatible NVA AFTER this hub exists.
}
resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value.cidr]
  tags                = local.tags
}
# Management is NOT hub-connected and never learns the Internet intent default.
resource "azurerm_virtual_network" "management" {
  name                = "management"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}
resource "azurerm_virtual_network_peering" "management_to_app" {
  name                         = "management-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.management.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke["app"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_virtual_network_peering" "app_to_management" {
  name                         = "app-to-management"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke["app"].name
  remote_virtual_network_id    = azurerm_virtual_network.management.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_subnet" "workload" {
  for_each                        = local.spokes
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke[each.key].name
  address_prefixes                = [each.value.workload]
  default_outbound_access_enabled = false
}
# No source route table: a 0/0->None would override the learned Internet default.
# Origin is deliberately UNCONNECTED to the hub and has no peering.
resource "azurerm_virtual_hub_connection" "app" {
  name                      = "connect-app"
  virtual_hub_id            = azurerm_virtual_hub.lab.id
  remote_virtual_network_id = azurerm_virtual_network.spoke["app"].id
  internet_security_enabled = true
  # No routing block: Internet intent owns Default association/propagation.
}
resource "azurerm_virtual_hub_routing_intent" "internet" {
  count          = var.enable_internet_intent ? 1 : 0
  name           = "internet-inspection"
  virtual_hub_id = azurerm_virtual_hub.lab.id
  routing_policy {
    name         = "InternetTrafficPolicy"
    destinations = ["Internet"]
    next_hop     = var.vendor_profile.nva_resource_id
  }
  depends_on = [azurerm_virtual_hub_connection.app]
  lifecycle {
    precondition {
      condition     = lower(var.vendor_profile.hub_resource_id) == lower(azurerm_virtual_hub.lab.id)
      error_message = "External NVA profile must name this exact owned hub; live identity and compatibility still need evidence."
    }
  }
}
resource "azurerm_public_ip" "origin" {
  name                = "origin-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
  lifecycle {
    postcondition {
      condition     = !contains(var.egress_public_ips, self.ip_address)
      error_message = "Origin public D must not be in the NVA egress E pool."
    }
  }
}
resource "azurerm_network_security_group" "workload" {
  for_each            = local.spokes
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  security_rule {
    name                       = each.key == "app" ? "test-egress" : "test-origin-ingress"
    priority                   = 100
    direction                  = each.key == "app" ? "Outbound" : "Inbound"
    access                     = local.test_nsg_action
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "8081"]
    source_address_prefix      = each.key == "app" ? "${local.app_ip}/32" : (length(var.egress_public_ips) == 0 ? "*" : null)
    source_address_prefixes    = each.key == "origin" && length(var.egress_public_ips) > 0 ? [for ip in sort(tolist(var.egress_public_ips)) : "${ip}/32"] : null
    destination_address_prefix = each.key == "app" ? "${azurerm_public_ip.origin.ip_address}/32" : "${local.origin_ip}/32"
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
    public_ip_address_id          = each.key == "origin" ? azurerm_public_ip.origin.id : null
    primary                       = true
  }
}
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = local.spokes
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.workload[each.key].id
}
