locals {
  test_ports = ["8080", "8081", "8082"]
  nsg_rules = {
    app = [
      { name = "test-origin", priority = 100, direction = "Outbound", action = local.test_nsg_action, source = "${local.app_ip}/32", destination = "${azurerm_public_ip.endpoint["origin"].ip_address}/32", source_ports = ["*"], ports = local.test_ports }
    ]
    perimeter = [
      { name = "test-transit-ingress", priority = 100, direction = "Inbound", action = local.test_nsg_action, source = local.source_prefix, destination = "${azurerm_public_ip.endpoint["origin"].ip_address}/32", source_ports = ["*"], ports = local.test_ports },
      { name = "test-translated-egress", priority = 101, direction = "Outbound", action = local.test_nsg_action, source = "${local.perimeter_ip}/32", destination = "${azurerm_public_ip.endpoint["origin"].ip_address}/32", source_ports = ["*"], ports = local.test_ports },
      { name = "test-restored-return", priority = 102, direction = "Outbound", action = local.test_nsg_action, source = "${azurerm_public_ip.endpoint["origin"].ip_address}/32", destination = local.source_prefix, source_ports = local.test_ports, ports = ["*"] }
    ]
    origin = [
      { name = "publish-controlled-fixtures", priority = 100, direction = "Inbound", action = local.origin_nsg_action, source = "${azurerm_public_ip.endpoint["perimeter"].ip_address}/32", destination = "${local.origin_ip}/32", source_ports = ["*"], ports = local.test_ports }
    ]
  }
}
resource "azurerm_network_security_group" "vm" {
  for_each            = local.workloads
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.nsg_rules[each.key]
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.action
      protocol                   = "Tcp"
      source_port_range          = length(security_rule.value.source_ports) == 1 ? one(security_rule.value.source_ports) : null
      source_port_ranges         = length(security_rule.value.source_ports) > 1 ? security_rule.value.source_ports : null
      destination_port_range     = length(security_rule.value.ports) == 1 ? one(security_rule.value.ports) : null
      destination_port_ranges    = length(security_rule.value.ports) > 1 ? security_rule.value.ports : null
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  security_rule {
    name                       = "management-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.management_prefix
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
  for_each              = local.workloads
  name                  = "${each.key}-nic"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  ip_forwarding_enabled = each.key == "perimeter"
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = each.key == "app" ? null : azurerm_public_ip.endpoint[each.key].id
    primary                       = true
  }
}
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = local.workloads
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.vm[each.key].id
}
