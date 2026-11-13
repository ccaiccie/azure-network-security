# Gates 1 and 5: small Linux VMs with no public IP.
#   vm-se-1       10.50.1.10  snet-se (service endpoint)             gate 1
#   vm-plain-1    10.50.4.10  snet-plain (no endpoint)               gate 1
#   vm-backend-1  10.60.1.10  snet-backend, behind the internal LB   gate 5
# The activities use curl on the consumer VMs and the backend's own small server, so no package install is needed.

locals {
  vms = merge(
    var.deploy_vms ? {
      "vm-se-1"    = { subnet_id = azurerm_subnet.se.id, ip = "10.50.1.10", role = "client" }
      "vm-plain-1" = { subnet_id = azurerm_subnet.plain.id, ip = "10.50.4.10", role = "client" }
    } : {},
    var.deploy_pls ? {
      "vm-backend-1" = { subnet_id = azurerm_subnet.backend.id, ip = "10.60.1.10", role = "backend" }
    } : {}
  )
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vms
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

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
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
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

  custom_data = each.value.role == "backend" ? base64encode(templatefile("${path.module}/scripts/cloud-init-backend.yaml", {
    backend_b64 = filebase64("${path.module}/scripts/backend.py")
  })) : null
}
