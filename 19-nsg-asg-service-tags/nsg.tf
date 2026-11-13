# The three subnet NSGs and the optional NIC-level NSG. NSGs and ASGs are free.
# Priorities leave gaps of 10 so a new rule can be slotted in between.

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                                       = "allow-web-from-internet"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_ranges                    = ["80", "443"]
    source_address_prefix                      = "Internet"
    destination_application_security_group_ids = [azurerm_application_security_group.web.id]
  }

  security_rule {
    name                                       = "allow-web-to-app-8080"
    priority                                   = 100
    direction                                  = "Outbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "8080"
    source_application_security_group_ids      = [azurerm_application_security_group.web.id]
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                                       = "allow-web-to-app-8080"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "8080"
    source_application_security_group_ids      = [azurerm_application_security_group.web.id]
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  security_rule {
    name                                       = "deny-vnet-to-app"
    priority                                   = 200
    direction                                  = "Inbound"
    access                                     = "Deny"
    protocol                                   = "*"
    source_port_range                          = "*"
    destination_port_range                     = "*"
    source_address_prefix                      = "VirtualNetwork"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  security_rule {
    name                                  = "allow-app-to-storage-443"
    priority                              = 100
    direction                             = "Outbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "443"
    source_application_security_group_ids = [azurerm_application_security_group.app.id]
    destination_address_prefix            = "Storage"
  }

  security_rule {
    name                                  = "deny-app-to-internet"
    priority                              = 4000
    direction                             = "Outbound"
    access                                = "Deny"
    protocol                              = "*"
    source_port_range                     = "*"
    destination_port_range                = "*"
    source_application_security_group_ids = [azurerm_application_security_group.app.id]
    destination_address_prefix            = "Internet"
  }
}

resource "azurerm_network_security_group" "pe" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "nsg-pe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                                  = "allow-app-to-pe-443"
    priority                              = 100
    direction                             = "Inbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "443"
    source_application_security_group_ids = [azurerm_application_security_group.app.id]
    destination_address_prefix            = "10.30.3.0/24"
  }

  security_rule {
    name                       = "deny-vnet-to-pe"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.30.3.0/24"
  }
}

# Second layer: an NSG on the app VM's NIC (gate attach_nic_nsg, needs deploy_vms).
resource "azurerm_network_security_group" "app_nic" {
  count               = var.deploy_vms && var.attach_nic_nsg ? 1 : 0
  name                = "nsg-app-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                                       = "deny-web-8080-at-nic"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Deny"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "8080"
    source_application_security_group_ids      = [azurerm_application_security_group.web.id]
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  count                     = var.deploy_private_endpoint ? 1 : 0
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe[0].id
}
