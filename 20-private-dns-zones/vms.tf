# Gates 1 and 2: small Linux VMs with no public IP.
#   vm-app-1   10.40.1.10  app VNet, registered in the private zone by autoregistration (gate 1)
#   vm-spoke-1 10.41.1.10  spoke VNet, resolves through its link but is NOT registered (gate 1)
#   dns-fwd    10.40.3.10  tiny UDP DNS forwarder in the app VNet (gate 2)
# Every VM gets /opt/lab/dnsq.py, a stdlib-only DNS client, so the activities need no package install.

locals {
  forwarder_upstream = var.break_fix == "public_forwarder" ? "9.9.9.9" : "168.63.129.16"

  vms = merge(
    var.deploy_vms ? {
      "vm-app-1"   = { subnet_id = azurerm_subnet.app_vm.id, ip = "10.40.1.10", role = "client" }
      "vm-spoke-1" = { subnet_id = azurerm_subnet.spoke_vm.id, ip = "10.41.1.10", role = "client" }
    } : {},
    var.deploy_custom_dns ? {
      "dns-fwd" = { subnet_id = azurerm_subnet.app_dns.id, ip = "10.40.3.10", role = "forwarder" }
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

  custom_data = base64encode(
    each.value.role == "forwarder" ? templatefile("${path.module}/scripts/cloud-init-dns.yaml", {
      dnsq_b64    = filebase64("${path.module}/scripts/dnsq.py")
      forward_b64 = filebase64("${path.module}/scripts/forward.py")
      listen_ip   = each.value.ip
      upstream    = local.forwarder_upstream
      }) : templatefile("${path.module}/scripts/cloud-init-vm.yaml", {
      dnsq_b64 = filebase64("${path.module}/scripts/dnsq.py")
    })
  )
}
