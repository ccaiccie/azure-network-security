# Gate 1 (deploy_vms): two small Linux VMs with no public IP, one in each subnet.
# web-1 10.30.1.10 is the client. app-1 10.30.2.10 runs a tiny web listener on TCP 8080.

resource "azurerm_network_interface" "web" {
  count               = var.deploy_vms ? 1 : 0
  name                = "web-1-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.30.1.10"
  }
}

resource "azurerm_network_interface" "app" {
  count               = var.deploy_vms ? 1 : 0
  name                = "app-1-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.30.2.10"
  }
}

# ASG membership: the NIC (not the VM, not the subnet) is what joins an ASG.
resource "azurerm_network_interface_application_security_group_association" "web" {
  count                         = var.deploy_vms && var.web_nic_in_asg ? 1 : 0
  network_interface_id          = azurerm_network_interface.web[0].id
  application_security_group_id = azurerm_application_security_group.web.id
}

resource "azurerm_network_interface_application_security_group_association" "app" {
  count                         = var.deploy_vms ? 1 : 0
  network_interface_id          = azurerm_network_interface.app[0].id
  application_security_group_id = azurerm_application_security_group.app.id
}

resource "azurerm_network_interface_security_group_association" "app_nic" {
  count                     = var.deploy_vms && var.attach_nic_nsg ? 1 : 0
  network_interface_id      = azurerm_network_interface.app[0].id
  network_security_group_id = azurerm_network_security_group.app_nic[0].id
}

resource "azurerm_linux_virtual_machine" "web" {
  count                           = var.deploy_vms ? 1 : 0
  name                            = "web-1"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.web[0].id]
  tags                            = local.tags

  admin_ssh_key {
    username   = "labadmin"
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key when deploy_vms is true."
    }
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  count                           = var.deploy_vms ? 1 : 0
  name                            = "app-1"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app[0].id]
  custom_data                     = base64encode(file("${path.module}/scripts/cloud-init-app.yaml"))
  tags                            = local.tags

  admin_ssh_key {
    username   = "labadmin"
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key when deploy_vms is true."
    }
  }
}
