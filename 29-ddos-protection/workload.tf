# Gate 1: the web VM, the protected public IP and a spare public IP attached to nothing.
# The lab never generates traffic. The spare IP exists to show what is NOT covered.

locals {
  # Empty override: Enabled with gate 4 (IP Protection, no plan ID), else follow the VNet.
  web_mode = var.pip_web_mode_override != "" ? var.pip_web_mode_override : (var.deploy_ip_protection ? "Enabled" : "VirtualNetworkInherited")
}

resource "azurerm_public_ip" "web" {
  count               = var.deploy_workload ? 1 : 0
  name                = "${var.name_prefix}-pip-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags

  # Enabled without a plan ID is IP Protection. VirtualNetworkInherited follows the VNet's plan link.
  ddos_protection_mode = local.web_mode
}

# Attached to nothing: even with a plan on the VNet there is no VNet resource to inherit from.
resource "azurerm_public_ip" "spare" {
  count                = var.deploy_workload ? 1 : 0
  name                 = "${var.name_prefix}-pip-spare"
  location             = azurerm_resource_group.lab.location
  resource_group_name  = azurerm_resource_group.lab.name
  allocation_method    = "Static"
  sku                  = "Standard"
  zones                = ["1", "2", "3"]
  ddos_protection_mode = "VirtualNetworkInherited"
  tags                 = local.tags
}

resource "azurerm_network_interface" "web" {
  count               = var.deploy_workload ? 1 : 0
  name                = "${var.name_prefix}-nic-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.90.1.4"
    public_ip_address_id          = azurerm_public_ip.web[0].id
  }
}

resource "azurerm_linux_virtual_machine" "web" {
  count                 = var.deploy_workload ? 1 : 0
  name                  = "vm-web"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.web[0].id]
  tags                  = local.tags

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
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOT
    #cloud-config
    packages:
      - nginx
    runcmd:
      - echo "ddos29 lab web server" > /var/www/html/index.html
  EOT
  )

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key (public key text) when deploy_workload is true."
    }
  }
}
