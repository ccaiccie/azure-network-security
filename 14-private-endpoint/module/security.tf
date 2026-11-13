resource "azurerm_network_security_group" "client" {
  for_each            = local.clients
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  security_rule {
    name                       = "owned-pe-https"
    priority                   = 100
    direction                  = "Outbound"
    access                     = local.client_actions[each.key]
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "${each.value}/32"
    destination_address_prefix = "${local.endpoint_ip}/32"
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
    destination_address_prefix = "${each.value}/32"
  }
  dynamic "security_rule" {
    for_each = { Udp = 200, Tcp = 201 }
    content {
      name                       = "firewall-dns-${lower(security_rule.key)}"
      priority                   = security_rule.value
      direction                  = "Outbound"
      access                     = local.dns_action
      protocol                   = security_rule.key
      source_port_range          = "*"
      destination_port_range     = "53"
      source_address_prefix      = "${each.value}/32"
      destination_address_prefix = "${azurerm_firewall.lab.ip_configuration[0].private_ip_address}/32"
    }
  }
  security_rule {
    name                       = "deny-platform-dns-bypass"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzurePlatformDNS"
  }
  security_rule {
    name      = "platform-imds"
    priority  = 220
    direction = "Outbound"
    access    = "Allow"
    # Cloud-init needs host-local IMDS metadata at boot; RBAC and Blob gates stay separate.
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${each.value}/32"
    destination_address_prefix = "AzurePlatformIMDS"
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
resource "azurerm_network_security_group" "endpoint" {
  name                = "endpoint-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  security_rule {
    name                       = "only-firewall-proxy-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = var.pe_ingress_enabled ? "Allow" : "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.1.0/26"
    destination_address_prefix = "${local.endpoint_ip}/32"
  }
  security_rule {
    name                       = "deny-other-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # No synthetic PE outbound/new-service-connection test or source-port restriction.
}
resource "azurerm_subnet_network_security_group_association" "endpoint" {
  subnet_id                 = azurerm_subnet.endpoint.id
  network_security_group_id = azurerm_network_security_group.endpoint.id
}
resource "azurerm_network_interface" "client" {
  for_each              = local.clients
  name                  = "${each.key}-nic"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  ip_forwarding_enabled = false
  dns_servers           = [azurerm_firewall.lab.ip_configuration[0].private_ip_address]
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value
    primary                       = true
  }
}
resource "azurerm_network_interface_security_group_association" "client" {
  for_each                  = local.clients
  network_interface_id      = azurerm_network_interface.client[each.key].id
  network_security_group_id = azurerm_network_security_group.client[each.key].id
}
