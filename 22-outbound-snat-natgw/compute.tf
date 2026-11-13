# Gate 1 (deploy_vms): three small Linux VMs, one per subnet, no public IP unless gate 5.
# vm-nat 10.50.1.10, vm-lb 10.50.2.10, vm-fw 10.50.3.10. They only make outbound calls; nothing listens.

resource "azurerm_public_ip" "vm_nat" {
  count               = var.deploy_vms && var.attach_vm_public_ip ? 1 : 0
  name                = "${var.name_prefix}-vmnat-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "nat" {
  count               = var.deploy_vms ? 1 : 0
  name                = "vm-nat-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.nat.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.1.10"
    public_ip_address_id          = one(azurerm_public_ip.vm_nat[*].id)
  }
}

resource "azurerm_network_interface" "lb" {
  count               = var.deploy_vms ? 1 : 0
  name                = "vm-lb-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lb.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.2.10"
  }
}

resource "azurerm_network_interface" "fw" {
  count               = var.deploy_vms ? 1 : 0
  name                = "vm-fw-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.fw.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.3.10"
  }
}

locals {
  vms = var.deploy_vms ? {
    "vm-nat" = azurerm_network_interface.nat[0].id
    "vm-lb"  = azurerm_network_interface.lb[0].id
    "vm-fw"  = azurerm_network_interface.fw[0].id
  } : {}
}

resource "azurerm_linux_virtual_machine" "lab" {
  for_each                        = local.vms
  name                            = each.key
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [each.value]
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
