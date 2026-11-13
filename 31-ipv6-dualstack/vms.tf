# Gate 1: two small Linux VMs with dual-stack NICs.
#   vm-web-1     10.31.1.10 + a dynamic IPv6 address from snet-web
#   vm-client-1  10.31.2.10 + a dynamic IPv6 address from snet-client
# Gate 3 adds a public IPv4 and a public IPv6 address to vm-client-1.
# Each VM serves a one-line page on TCP 8080 over both families (python3 http.server bound to ::).

locals {
  vms = var.deploy_vms ? {
    "vm-web-1"    = { subnet_id = azurerm_subnet.web.id, ip = "10.31.1.10" }
    "vm-client-1" = { subnet_id = azurerm_subnet.client.id, ip = "10.31.2.10" }
  } : {}
}

resource "azurerm_public_ip" "client_v4" {
  count               = var.deploy_vms && var.deploy_client_ips ? 1 : 0
  name                = "${local.p}-client-pip4"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  allocation_method   = "Static"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_public_ip" "client_v6" {
  count               = var.deploy_vms && var.deploy_client_ips ? 1 : 0
  name                = "${local.p}-client-pip6"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  allocation_method   = "Static"
  ip_version          = "IPv6"
  tags                = local.tags
}

# The first IP configuration must be the IPv4 one (primary). The IPv6 configuration is a second one on the same NIC.
resource "azurerm_network_interface" "vm" {
  for_each            = local.vms
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    primary                       = true
    subnet_id                     = each.value.subnet_id
    private_ip_address_version    = "IPv4"
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = each.key == "vm-client-1" && var.deploy_client_ips ? azurerm_public_ip.client_v4[0].id : null
  }

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = each.value.subnet_id
    private_ip_address_version    = "IPv6"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.key == "vm-client-1" && var.deploy_client_ips ? azurerm_public_ip.client_v6[0].id : null
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

  custom_data = base64encode(templatefile("${path.module}/scripts/cloud-init-web.yaml", {
    vm_name = each.key
  }))

  lifecycle {
    precondition {
      condition     = length(var.admin_ssh_public_key) > 0
      error_message = "Set admin_ssh_public_key (the text of a public key) before opening gate 1."
    }
  }
}

# Names in the private zone: web.ds31.internal has an A record and, unless break_fix = no_aaaa, an AAAA record.
resource "azurerm_private_dns_a_record" "web" {
  count               = var.deploy_vms ? 1 : 0
  name                = "web"
  zone_name           = azurerm_private_dns_zone.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 60
  records             = ["10.31.1.10"]
}

resource "azurerm_private_dns_aaaa_record" "web" {
  count               = var.deploy_vms && var.break_fix != "no_aaaa" ? 1 : 0
  name                = "web"
  zone_name           = azurerm_private_dns_zone.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 60
  records             = [azurerm_network_interface.vm["vm-web-1"].private_ip_addresses[1]]
}
