locals {
  hub_cidr         = "10.0.0.0/16"
  firewall_cidr    = "10.0.1.0/26"
  bastion_cidr     = "10.0.2.0/26"
  app_ip           = "10.10.1.10"
  backend_ip       = "10.20.1.10"
  firewall_ip      = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  rules_enabled    = var.fixtures_ready && var.policy_mode != "closed"
  override_enabled = local.rules_enabled && contains(["network-allow", "network-deny"], var.policy_mode)
  override_action  = var.policy_mode == "network-allow" ? "Allow" : "Deny"
  tags             = merge(var.tags, { purpose = "disposable-policy-lab", managed_by = "terraform" })
  workloads = {
    app     = { vnet_cidr = "10.10.0.0/16", subnet_cidr = "10.10.1.0/24", private_ip = local.app_ip, remote_cidr = "10.20.0.0/16" }
    backend = { vnet_cidr = "10.20.0.0/16", subnet_cidr = "10.20.1.0/24", private_ip = local.backend_ip, remote_cidr = "10.10.0.0/16" }
  }
  route_specs = {
    for role, w in local.workloads : role => [
      { name = "default", prefix = "0.0.0.0/0", type = "VirtualAppliance" },
      { name = "remote-spoke", prefix = w.remote_cidr, type = "VirtualAppliance" }
    ]
  }
  test_nsg_rules = {
    app = [
      { name = "allow-backend-tests", priority = 100, direction = "Outbound", source = "${local.app_ip}/32", destination = "${local.backend_ip}/32", ports = ["8080", "8081"] }
    ]
    backend = [
      { name = "allow-direct-app-tests", priority = 100, direction = "Inbound", source = "${local.app_ip}/32", destination = "${local.backend_ip}/32", ports = ["8080", "8081"] },
      { name = "allow-proxy-tests", priority = 101, direction = "Inbound", source = local.firewall_cidr, destination = "${local.backend_ip}/32", ports = ["8080", "8081"] }
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
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.firewall_cidr]
  # No customer NSG or UDR on the managed firewall subnet.
}
resource "azurerm_public_ip" "firewall" {
  name                = "firewall-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
resource "azurerm_firewall_policy" "lab" {
  name                     = "lab-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags
  dns { proxy_enabled = true }
  # No inheritance, SNAT override, IDPS, TLS, explicit proxy or access grant.
}
resource "azurerm_firewall_policy_rule_collection_group" "application" {
  count              = local.rules_enabled ? 1 : 0
  name               = "app-controls"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  application_rule_collection {
    name     = "deny-test-host"
    priority = 100
    action   = "Deny"
    rule {
      name              = "deny-denied-host"
      source_addresses  = ["${local.app_ip}/32"]
      destination_fqdns = ["denied.policy.test"]
      protocols {
        type = "Http"
        port = 8080
      }
    }
  }
  application_rule_collection {
    name     = "allow-test-host"
    priority = 200
    action   = "Allow"
    rule {
      name              = "allow-approved-host"
      source_addresses  = ["${local.app_ip}/32"]
      destination_fqdns = ["allowed.policy.test"]
      protocols {
        type = "Http"
        port = 8080
      }
    }
  }
}
resource "azurerm_firewall_policy_rule_collection_group" "negative" {
  count              = local.rules_enabled ? 1 : 0
  name               = "negative-controls"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 300
  network_rule_collection {
    name     = "deny-alternate-port"
    priority = 100
    action   = "Deny"
    rule {
      name                  = "deny-app-alternate-port"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = ["${local.backend_ip}/32"]
      destination_ports     = ["8081"]
    }
  }
}
resource "azurerm_firewall_policy_rule_collection_group" "override" {
  count              = local.override_enabled ? 1 : 0
  name               = "network-override"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 65000
  network_rule_collection {
    name     = local.override_action == "Allow" ? "allow-exact-backend" : "deny-exact-backend"
    priority = 65000
    action   = local.override_action
    rule {
      name                  = local.override_action == "Allow" ? "allow-app-backend" : "deny-app-backend"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = ["${local.backend_ip}/32"]
      destination_ports     = ["8080"]
    }
  }
}
resource "azurerm_firewall" "lab" {
  name                = "lab-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  tags                = local.tags
  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  depends_on = [azurerm_firewall_policy_rule_collection_group.application, azurerm_firewall_policy_rule_collection_group.negative, azurerm_firewall_policy_rule_collection_group.override]
}
resource "azurerm_virtual_network" "workload" {
  for_each            = local.workloads
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value.vnet_cidr]
  dns_servers         = [local.firewall_ip]
  tags                = local.tags
}
resource "azurerm_subnet" "workload" {
  for_each                        = local.workloads
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.workload[each.key].name
  address_prefixes                = [each.value.subnet_cidr]
  default_outbound_access_enabled = false
}

# Explicitly serialize peering operations. There is no app-to-backend direct peering.
resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.workload["app"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.workload["app"].name
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
  remote_virtual_network_id    = azurerm_virtual_network.workload["backend"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.app_to_hub]
}

resource "azurerm_virtual_network_peering" "backend_to_hub" {
  name                         = "backend-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.workload["backend"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_backend]
}

resource "azurerm_route_table" "workload" {
  for_each                      = local.workloads
  name                          = "${each.key}-inspect"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  dynamic "route" {
    for_each = local.route_specs[each.key]
    content {
      name                   = route.value.name
      address_prefix         = route.value.prefix
      next_hop_type          = route.value.type
      next_hop_in_ip_address = route.value.type == "VirtualAppliance" ? local.firewall_ip : null
    }
  }
}

resource "azurerm_subnet_route_table_association" "workload" {
  for_each       = local.workloads
  subnet_id      = azurerm_subnet.workload[each.key].id
  route_table_id = azurerm_route_table.workload[each.key].id
}

resource "azurerm_network_security_group" "workload" {
  for_each            = local.workloads
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
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bastion_cidr
    destination_address_prefix = "${each.value.private_ip}/32"
  }
  dynamic "security_rule" {
    for_each = { Udp = 200, Tcp = 201 }
    content {
      name                       = "allow-dns-proxy-${lower(security_rule.key)}"
      priority                   = security_rule.value
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = security_rule.key
      source_port_range          = "*"
      destination_port_range     = "53"
      source_address_prefix      = "${each.value.private_ip}/32"
      destination_address_prefix = "${local.firewall_ip}/32"
    }
  }
  security_rule {
    name                       = "deny-direct-platform-dns"
    priority                   = 210
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

resource "azurerm_subnet_network_security_group_association" "workload" {
  for_each                  = local.workloads
  subnet_id                 = azurerm_subnet.workload[each.key].id
  network_security_group_id = azurerm_network_security_group.workload[each.key].id
}

resource "azurerm_network_interface" "workload" {
  for_each            = local.workloads
  name                = "${each.key}-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

