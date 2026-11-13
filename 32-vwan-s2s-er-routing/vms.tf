# Gate 2 (deploy_vms): one small VM per spoke, with no public IP. Reach them with az vm run-command.
# Gate 7 (deploy_nva_bgp): vm-nva in the shared spoke runs FRR and peers with the hub 1 router.

locals {
  vm_spokes = {
    prod   = { ip = "10.101.0.4", region = 1 }
    dev    = { ip = "10.102.0.4", region = 1 }
    shared = { ip = "10.103.0.4", region = 1 }
    eu2    = { ip = "10.201.0.4", region = 2 }
  }
  vms_on = {
    for k, v in local.vm_spokes : k => v
    if var.deploy_vms && (k != "eu2" || var.deploy_hub2)
  }
  nva_on = var.deploy_nva_bgp && var.deploy_vms && var.deploy_hub1
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vms_on
  name                = "vm-${each.key}-nic"
  location            = each.value.region == 1 ? var.location : var.location2
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.spoke[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.vms_on
  name                            = "vm-${each.key}"
  location                        = each.value.region == 1 ? var.location : var.location2
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  tags                            = local.tags

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

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key before opening gate 2."
    }
  }
}

# ---------------------------------------------------------------- NVA that peers with the hub router (gate 7)

resource "azurerm_network_interface" "nva" {
  count                 = local.nva_on ? 1 : 0
  name                  = "vm-nva-nic"
  location              = var.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.spoke["shared"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.103.0.10"
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  count                           = local.nva_on ? 1 : 0
  name                            = "vm-nva"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nva[0].id]
  tags                            = local.tags

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

  custom_data = base64encode(templatefile("${path.module}/scripts/nva-setup.sh.tftpl", {
    router_ips = azurerm_virtual_hub.hub1[0].virtual_router_ips
    hub_asn    = azurerm_virtual_hub.hub1[0].virtual_router_asn
    nva_asn    = 65030
    advertise  = "10.250.0.0/24"
  }))
}

# The hub router peers with the NVA. The NVA's ASN must not be one of the reserved ones; check current docs.
resource "azurerm_virtual_hub_bgp_connection" "nva" {
  count                         = local.nva_on ? 1 : 0
  name                          = "bgp-nva"
  virtual_hub_id                = azurerm_virtual_hub.hub1[0].id
  peer_asn                      = 65030
  peer_ip                       = "10.103.0.10"
  virtual_network_connection_id = azurerm_virtual_hub_connection.shared[0].id
}
