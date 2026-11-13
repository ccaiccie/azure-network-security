# Gate 2: the on-premises stand-in VM. It answers tcp/8080 with the caller address it saw.
# No public IP: you reach it only from the cluster over the peering.

resource "azurerm_network_interface" "onprem" {
  count               = var.deploy_onprem_vm ? 1 : 0
  name                = "onprem-1-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.onprem.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.1.4"
  }
}

resource "azurerm_linux_virtual_machine" "onprem" {
  count                           = var.deploy_onprem_vm ? 1 : 0
  name                            = "onprem-1"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.node_vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.onprem[0].id]
  custom_data                     = base64encode(file("${path.module}/scripts/cloud-init-onprem.yaml"))
  tags                            = local.tags

  admin_ssh_key {
    username   = "azureuser"
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

  lifecycle {
    precondition {
      condition     = length(var.admin_ssh_public_key) > 20
      error_message = "Set admin_ssh_public_key to the text of a public key when deploy_onprem_vm is true."
    }
  }
}
