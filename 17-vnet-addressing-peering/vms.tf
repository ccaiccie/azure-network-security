# Small Ubuntu VMs with private IPs only. They exist so that effective routes can be read from a NIC.
locals {
  ssh_key = var.admin_ssh_public_key

  vms = merge(
    var.deploy_vms ? {
      "vm-hub" = { subnet_id = azurerm_subnet.hub_shared.id, ip = "10.0.1.4", location = var.location }
      "vm-a"   = { subnet_id = azurerm_subnet.spoke_a_app.id, ip = "10.10.1.4", location = var.location }
      "vm-b"   = { subnet_id = azurerm_subnet.spoke_b_app.id, ip = cidrhost(local.spoke_b_subnet, 4), location = var.location }
    } : {},
    var.deploy_vms && var.create_global_peering ? {
      "vm-c" = { subnet_id = azurerm_subnet.spoke_c_app[0].id, ip = "10.30.1.4", location = var.secondary_location }
    } : {}
  )
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vms
  name                = "nic-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.vms
  name                            = each.key
  location                        = each.value.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = local.ssh_key
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
      condition     = length(trimspace(var.admin_ssh_public_key)) > 0
      error_message = "deploy_vms needs admin_ssh_public_key: an existing OpenSSH public key."
    }
  }
}
