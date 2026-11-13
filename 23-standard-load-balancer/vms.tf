# Two web VMs behind the load balancer and one client. Private IPs only; cloud-init needs no Internet.
locals {
  web_vms = var.deploy_vms ? {
    "vm-web1" = { ip = local.web1_ip }
    "vm-web2" = { ip = local.web2_ip }
  } : {}

  client_vms = var.deploy_vms ? { "vm-client" = { ip = local.client_ip } } : {}
}

resource "azurerm_network_interface" "web" {
  for_each            = local.web_vms
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_network_interface" "client" {
  for_each            = local.client_vms
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
  for_each                = local.web_vms
  network_interface_id    = azurerm_network_interface.web[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id
}

resource "azurerm_network_interface_nat_rule_association" "web1" {
  count                 = var.create_nat_rule && var.deploy_vms ? 1 : 0
  network_interface_id  = azurerm_network_interface.web["vm-web1"].id
  ip_configuration_name = "ipconfig1"
  nat_rule_id           = azurerm_lb_nat_rule.ssh_web1[0].id
}

resource "azurerm_linux_virtual_machine" "web" {
  for_each                        = local.web_vms
  name                            = each.key
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.web[each.key].id]
  tags                            = var.tags

  # The frontend address goes on the loopback only when floating IP is on (direct server return).
  custom_data = base64encode(templatefile("${path.module}/scripts/web-cloud-init.yaml", {
    loopback_ip = var.floating_ip ? local.frontend_ip : ""
  }))

  admin_ssh_key {
    username   = "azureuser"
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
      condition     = length(trimspace(var.admin_ssh_public_key)) > 0
      error_message = "deploy_vms needs admin_ssh_public_key: an existing OpenSSH public key."
    }
  }
}

resource "azurerm_linux_virtual_machine" "client" {
  for_each                        = local.client_vms
  name                            = each.key
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.client[each.key].id]
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
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
