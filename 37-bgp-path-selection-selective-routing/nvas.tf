# Gate 2 (deploy_nvas): two FRR routers in snet-nva that act as simulated on-premises or NVA BGP speakers,
# plus vm-app in snet-app, whose effective routes show what Route Server programmed.
#   nva-a 10.37.1.4  ASN var.nva_a_asn     nva-b 10.37.1.5  ASN var.nva_b_asn     vm-app 10.37.2.4
# Both NVAs announce 10.99.0.0/24 (the simulated on-premises prefix). Activities change their attributes.

locals {
  nvas_on = var.deploy_route_server && var.deploy_nvas
  rs_ips  = local.nvas_on ? tolist(azurerm_route_server.rs[0].virtual_router_ips) : []
  nva_def = {
    "nva-a" = { ip = "10.37.1.4", asn = var.nva_a_asn }
    "nva-b" = { ip = "10.37.1.5", asn = var.nva_b_asn }
  }
}

resource "azurerm_public_ip" "nva" {
  for_each            = local.nvas_on ? local.nva_def : {}
  name                = "${each.key}-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# The public IPs exist only so the boot script can install packages. A Standard public IP accepts no inbound traffic without an NSG rule.
resource "azurerm_network_interface" "nva" {
  for_each              = local.nvas_on ? local.nva_def : {}
  name                  = "${each.key}-nic"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = azurerm_public_ip.nva[each.key].id
  }
}

resource "azurerm_network_interface" "app" {
  count               = local.nvas_on ? 1 : 0
  name                = "vm-app-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.37.2.4"
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  for_each                        = local.nvas_on ? local.nva_def : {}
  name                            = each.key
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nva[each.key].id]
  tags                            = local.tags

  custom_data = base64encode(templatefile("${path.module}/scripts/frr-setup.sh.tftpl", {
    hostname      = each.key
    asn           = each.value.asn
    router_id     = each.value.ip
    rs_ips        = local.rs_ips
    render_script = file("${path.module}/scripts/frr-render.sh")
  }))

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
      error_message = "Set admin_ssh_public_key when deploy_nvas is true."
    }
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  count                           = local.nvas_on ? 1 : 0
  name                            = "vm-app"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app[0].id]
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
}
