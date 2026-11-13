resource "azurerm_network_interface" "a" {
  count               = local.on
  name                = "nic-a"
  location            = azurerm_resource_group.lab[0].location
  resource_group_name = azurerm_resource_group.lab[0].name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.app[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.app_ip
  }
}

# The appliance NIC is the only one with IP forwarding (switched off by fault=forwarding_off).
resource "azurerm_network_interface" "nva" {
  count                 = local.on
  name                  = "nic-nva"
  location              = azurerm_resource_group.lab[0].location
  resource_group_name   = azurerm_resource_group.lab[0].name
  ip_forwarding_enabled = local.nva_forwarding

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.nva[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.nva_ip
  }
}

resource "azurerm_network_interface" "b" {
  count               = local.on
  name                = "nic-b"
  location            = azurerm_resource_group.lab[0].location
  resource_group_name = azurerm_resource_group.lab[0].name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.work[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.work_ip
  }
}

locals {
  vms = {
    "vm-a"   = { nic = "a", custom_data = null }
    "vm-nva" = { nic = "nva", custom_data = templatefile("${path.module}/cloud-init/nva.yaml.tftpl", { app_cidr = "10.10.1.0/24", work_cidr = "10.20.1.0/24" }) }
    "vm-b"   = { nic = "b", custom_data = templatefile("${path.module}/cloud-init/web.yaml.tftpl", {}) }
  }
  nic_ids = local.on == 1 ? {
    "a"   = azurerm_network_interface.a[0].id
    "nva" = azurerm_network_interface.nva[0].id
    "b"   = azurerm_network_interface.b[0].id
  } : {}
}

resource "azurerm_linux_virtual_machine" "lab" {
  for_each = local.on == 1 ? local.vms : {}

  name                            = each.key
  location                        = azurerm_resource_group.lab[0].location
  resource_group_name             = azurerm_resource_group.lab[0].name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [local.nic_ids[each.value.nic]]
  custom_data                     = each.value.custom_data == null ? null : base64encode(each.value.custom_data)

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
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
