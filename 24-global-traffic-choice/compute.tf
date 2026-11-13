# Gate 1 (deploy_backends), part 1: two small Linux VMs that run nginx and print what they see.
# The VMs have no public IP. Outbound access for the package install comes from the load balancer rule in lb.tf.

resource "azurerm_network_interface" "web" {
  count               = var.deploy_backends ? 2 : 0
  name                = "${var.name_prefix}-web${count.index + 1}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.web_ips[count.index]
  }
}

resource "azurerm_linux_virtual_machine" "web" {
  count                           = var.deploy_backends ? 2 : 0
  name                            = "web${count.index + 1}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.web[count.index].id]
  custom_data                     = filebase64("${path.module}/scripts/cloud-init-web.yaml")
  tags                            = local.tags

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

  # The package install needs outbound access, which exists only after the NIC is in the load balancer pool.
  depends_on = [azurerm_network_interface_backend_address_pool_association.web]
}
