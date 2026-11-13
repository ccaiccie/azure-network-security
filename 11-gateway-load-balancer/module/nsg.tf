resource "azurerm_network_security_group" "vm" {
  for_each            = local.nodes
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = each.key == "app" ? [1] : []
    content {
      name                       = "test-client-ingress"
      priority                   = 100
      direction                  = "Inbound"
      access                     = local.test_nsg_action
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["8080", "8081"]
      source_address_prefix      = "${var.client_public_ip}/32"
      destination_address_prefix = "${each.value.ip}/32"
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
    name                       = "platform-readiness"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = each.key == "app" ? "8009" : "8008"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "${each.value.ip}/32"
  }
  dynamic "security_rule" {
    for_each = each.key == "app" ? [] : ["Inbound", "Outbound"]
    content {
      name                       = "vxlan-${lower(security_rule.value)}"
      priority                   = 130
      direction                  = security_rule.value
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_ranges    = ["10800", "10801"]
      source_address_prefix      = security_rule.value == "Inbound" ? "10.0.0.0/16" : "${each.value.ip}/32"
      destination_address_prefix = security_rule.value == "Inbound" ? "${each.value.ip}/32" : "10.0.0.0/16"
    }
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
resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = local.nodes
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.vm[each.key].id
}
