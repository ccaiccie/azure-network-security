# Gate 1: vm-app in the spoke with NO public IP (unless vm_public_ip is set for the JIT demonstration),
# its NSG, an optional second NSG on the NIC (break/fix 2) and the hub-spoke peering (break/fix 3).

resource "azurerm_network_security_group" "app" {
  count               = var.deploy_workload ? 1 : 0
  name                = "${var.name_prefix}-nsg-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  # Only the Bastion subnet may reach SSH. JIT (Defender) adds and removes its own rules in this NSG.
  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bastion_subnet_prefix
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  count                     = var.deploy_workload ? 1 : 0
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app[0].id
}

# Break/fix 2: a second NSG on the NIC. Both NSGs must allow a packet; JIT edits only one of them.
resource "azurerm_network_security_group" "nic" {
  count               = var.deploy_workload && var.nic_nsg_blocks_ssh ? 1 : 0
  name                = "${var.name_prefix}-nsg-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "deny-ssh-from-internet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Temporary public IP, ONLY for the JIT demonstration in Activity 5. Remove it afterwards.
resource "azurerm_public_ip" "vm" {
  count               = var.deploy_workload && var.vm_public_ip ? 1 : 0
  name                = "${var.name_prefix}-pip-vm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "app" {
  count               = var.deploy_workload ? 1 : 0
  name                = "${var.name_prefix}-nic-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.34.1.4"
    public_ip_address_id          = var.vm_public_ip ? azurerm_public_ip.vm[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "nic" {
  count                     = var.deploy_workload && var.nic_nsg_blocks_ssh ? 1 : 0
  network_interface_id      = azurerm_network_interface.app[0].id
  network_security_group_id = azurerm_network_security_group.nic[0].id
}

resource "azurerm_linux_virtual_machine" "app" {
  count                 = var.deploy_workload ? 1 : 0
  name                  = "${var.name_prefix}-vm-app"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.app[0].id]
  tags                  = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Managed boot diagnostics: needed for the serial console break-glass path.
  boot_diagnostics {}

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key (public key text) when deploy_workload is true."
    }
  }
}

# Peering in both directions. Break/fix 3: set peer_spoke_to_hub = false and Bastion loses the path.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                     = var.deploy_workload && var.peer_spoke_to_hub ? 1 : 0
  name                      = "hub-to-spoke"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                     = var.deploy_workload && var.peer_spoke_to_hub ? 1 : 0
  name                      = "spoke-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
}
