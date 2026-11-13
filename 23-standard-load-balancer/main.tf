locals {
  vnet_space     = "10.23.0.0/16"
  web_subnet     = "10.23.1.0/24"
  client_subnet  = "10.23.2.0/24"
  frontend_ip    = "10.23.1.10"
  ha_frontend_ip = "10.23.1.11"
  web1_ip        = "10.23.1.4"
  web2_ip        = "10.23.1.5"
  client_ip      = "10.23.2.4"

  # break_fix = probe_port probes TCP 8081, where nothing listens: every backend looks down.
  probe_port = var.break_fix == "probe_port" ? 8081 : 80
  # break_fix = affinity turns on source-IP persistence on the main rule.
  distribution = var.break_fix == "affinity" ? "SourceIP" : var.session_persistence
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-lb-lab"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.vnet_space]
  tags                = var.tags
}

# Both subnets are private: no default outbound access, so the guests install nothing from the Internet.
resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = [local.web_subnet]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "client" {
  name                            = "snet-client"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = [local.client_subnet]
  default_outbound_access_enabled = false
}

# ------------------------------------------------------------------ NSG on the backend subnet
# The default rule AllowAzureLoadBalancerInBound (65001) lets the probe in. With break_fix = nsg_probe a custom
# deny-all rule at priority 200 sits in front of it and the probe is blocked.
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  security_rule {
    name                       = "allow-http-from-clients"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "8080"]
    source_address_prefix      = local.client_subnet
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-from-backends"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "8080"]
    source_address_prefix      = local.web_subnet
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.create_nat_rule ? [1] : []
    content {
      name                       = "allow-ssh-from-clients"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = local.client_subnet
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.create_public_lb ? [1] : []
    content {
      name                       = "allow-http-from-internet"
      priority                   = 130
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.break_fix == "nsg_probe" ? [1] : []
    content {
      name                       = "deny-all-inbound-hardening"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}
