# Gate 1 (deploy_vms): vm-client 10.80.0.10 and vm-server 10.81.0.10 (serves HTTP on app_port). No public IPs.
# Use `az vm run-command` (the Azure agent) to run curl: no inbound access is needed.
# The Network Watcher agent extension is what Connection Monitor, connection troubleshoot and packet capture need on the VM.

locals {
  vms = var.deploy_vms ? {
    client = { subnet = azurerm_subnet.client.id, ip = "10.80.0.10" }
    server = { subnet = azurerm_subnet.server.id, ip = "10.81.0.10" }
  } : {}
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vms
  name                = "vm-${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = each.value.subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.vms
  name                            = "vm-${each.key}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  custom_data                     = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml.tftpl", { app_port = var.app_port }))
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
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "watcher_agent" {
  for_each                   = local.vms
  name                       = "NetworkWatcherAgentLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm[each.key].id
  publisher                  = "Microsoft.Azure.NetworkWatcher"
  type                       = "NetworkWatcherAgentLinux"
  type_handler_version       = "1.4"
  auto_upgrade_minor_version = true
}
