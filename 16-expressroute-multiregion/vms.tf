# Optional: one small VM per spoke so that effective routes have a NIC to show.
# No public IP. Reach it from your on-premises host once the circuit works.

resource "azurerm_network_interface" "vm" {
  for_each = local.vms

  name                = "${var.name_prefix}-nic-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab[0].name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.vm_ip
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.vms

  name                            = "${var.name_prefix}-vm-${each.key}"
  location                        = each.value.location
  resource_group_name             = azurerm_resource_group.lab[0].name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  disable_password_authentication = true
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

  lifecycle {
    precondition {
      condition     = length(var.admin_ssh_public_key) > 0
      error_message = "Set admin_ssh_public_key when deploy_test_vms is true."
    }
  }
}
