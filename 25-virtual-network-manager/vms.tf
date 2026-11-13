# Gate 5 (deploy_vms): three small Linux VMs, one per spoke, and an NSG on the three spoke subnets.
# vm-a 10.71.0.10, vm-b 10.72.0.10 (serves HTTP on app_port), vm-c 10.73.0.10. No public IPs.
# Use `az vm run-command` (the Azure agent) to run curl: no inbound access is needed.

locals {
  vms = var.deploy_vms ? {
    a = { subnet = azurerm_subnet.a.id, ip = "10.71.0.10" }
    b = { subnet = azurerm_subnet.b.id, ip = "10.72.0.10" }
    c = { subnet = azurerm_subnet.c.id, ip = "10.73.0.10" }
  } : {}
}

resource "azurerm_network_security_group" "spokes" {
  count               = var.deploy_vms ? 1 : 0
  name                = "${var.name_prefix}-nsg-spokes"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "app-port"
    priority                   = 100
    direction                  = "Inbound"
    access                     = var.nsg_allows_app_port ? "Allow" : "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.app_port)
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "a" {
  count                     = var.deploy_vms ? 1 : 0
  subnet_id                 = azurerm_subnet.a.id
  network_security_group_id = azurerm_network_security_group.spokes[0].id
}

resource "azurerm_subnet_network_security_group_association" "b" {
  count                     = var.deploy_vms ? 1 : 0
  subnet_id                 = azurerm_subnet.b.id
  network_security_group_id = azurerm_network_security_group.spokes[0].id
}

resource "azurerm_subnet_network_security_group_association" "c" {
  count                     = var.deploy_vms ? 1 : 0
  subnet_id                 = azurerm_subnet.c.id
  network_security_group_id = azurerm_network_security_group.spokes[0].id
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
