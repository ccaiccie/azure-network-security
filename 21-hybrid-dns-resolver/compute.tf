# Gate 3 (deploy_vms): three small Linux VMs with no public IP.
#   spoke-vm       10.51.1.10  asks Azure DNS (and the ruleset) for names
#   onprem-dns     10.60.1.10  dnsmasq: the stand-in on-premises DNS server and conditional forwarder
#   onprem-client  10.60.1.20  asks onprem-dns, like an on-premises workstation

locals {
  vms = {
    "spoke-vm"      = { subnet = azurerm_subnet.workload.id, ip = "10.51.1.10", custom_data = file("${path.module}/scripts/cloud-init-tools.yaml") }
    "onprem-dns"    = { subnet = azurerm_subnet.servers.id, ip = "10.60.1.10", custom_data = templatefile("${path.module}/scripts/cloud-init-onprem-dns.yaml.tftpl", { inbound_ip = local.inbound_ip }) }
    "onprem-client" = { subnet = azurerm_subnet.servers.id, ip = "10.60.1.20", custom_data = file("${path.module}/scripts/cloud-init-tools.yaml") }
  }
}

resource "azurerm_network_interface" "vm" {
  for_each            = var.deploy_vms ? local.vms : {}
  name                = "${each.key}-nic"
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
  for_each                        = var.deploy_vms ? local.vms : {}
  name                            = each.key
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  custom_data                     = base64encode(each.value.custom_data)
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
