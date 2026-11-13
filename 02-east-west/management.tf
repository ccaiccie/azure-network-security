# Management path deliberately separate from the tested east-west policy.
# Bastion Standard permits local native SSH/tunneling and needs no public IP on VM.
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.bastion_cidr]
  # No workload-inspection route table is attached here.
}

resource "azurerm_public_ip" "bastion" {
  name                = "bastion-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}

locals {
  # All mandatory Bastion service rules. These do NOT apply to workload egress.
  bastion_rules = {
    allow-https-in = {
      priority = 100, direction = "Inbound", protocol = "Tcp"
      source   = "Internet", destination = "*", ports = ["443"]
    }
    allow-gateway-manager-in = {
      priority = 110, direction = "Inbound", protocol = "Tcp"
      source   = "GatewayManager", destination = "*", ports = ["443"]
    }
    allow-service-in = {
      priority = 120, direction = "Inbound", protocol = "*"
      source   = "VirtualNetwork", destination = "VirtualNetwork", ports = ["8080", "5701"]
    }
    allow-load-balancer-in = {
      priority = 130, direction = "Inbound", protocol = "Tcp"
      source   = "AzureLoadBalancer", destination = "*", ports = ["443"]
    }
    allow-ssh-rdp-out = {
      priority = 100, direction = "Outbound", protocol = "*"
      source   = "*", destination = "VirtualNetwork", ports = ["22", "3389"]
    }
    allow-azure-control-out = {
      priority = 110, direction = "Outbound", protocol = "Tcp"
      source   = "*", destination = "AzureCloud", ports = ["443"]
    }
    allow-service-out = {
      priority = 120, direction = "Outbound", protocol = "*"
      source   = "VirtualNetwork", destination = "VirtualNetwork", ports = ["8080", "5701"]
    }
    allow-http-out = {
      priority = 130, direction = "Outbound", protocol = "*"
      source   = "*", destination = "Internet", ports = ["80"]
    }
  }
}

resource "azurerm_network_security_group" "bastion" {
  name                = "bastion-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.bastion_rules
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }

  dynamic "security_rule" {
    for_each = toset(["Inbound", "Outbound"])
    content {
      name                       = "deny-other-${lower(security_rule.key)}"
      priority                   = 4096
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

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_bastion_host" "lab" {
  name                   = "ew-bastion"
  resource_group_name    = azurerm_resource_group.lab.name
  location               = azurerm_resource_group.lab.location
  sku                    = "Standard"
  scale_units            = 2
  tunneling_enabled      = true
  copy_paste_enabled     = true
  shareable_link_enabled = false
  tags                   = local.tags

  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  depends_on = [azurerm_subnet_network_security_group_association.bastion]
}
