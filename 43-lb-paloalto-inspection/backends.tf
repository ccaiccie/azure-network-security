# Gate 2: two small web VMs in snet-web and the web tier's internal Standard load balancer. The firewall's DNAT rule
# targets the load balancer frontend, so the firewall does not have to know which web VM is alive.

locals {
  web_vms = {
    "web-1" = { ip = "10.81.0.4" }
    "web-2" = { ip = "10.81.0.5" }
  }
  web_on = var.deploy_backends ? local.web_vms : {}
}

resource "azurerm_network_interface" "web" {
  for_each            = local.web_on
  name                = "${local.p}-${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

# The boot script starts a tiny web server that answers "lab <name>" on tcp/80 and logs the client address.
resource "azurerm_linux_virtual_machine" "web" {
  for_each                        = local.web_on
  name                            = "${local.p}-${each.key}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.web_vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.web[each.key].id]
  custom_data                     = base64encode(replace(file("${path.module}/scripts/web-init.sh"), "__NAME__", each.key))
  tags                            = local.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  lifecycle {
    precondition {
      condition     = var.admin_password != null
      error_message = "Set admin_password through TF_VAR_admin_password or your secret store."
    }
  }
}

resource "azurerm_lb" "web" {
  count               = var.deploy_backends ? 1 : 0
  name                = "${local.p}-weblb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                          = "fe-web"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.web_ilb_frontend_ip
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  count           = var.deploy_backends ? 1 : 0
  name            = "web-vms"
  loadbalancer_id = azurerm_lb.web[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
  for_each                = local.web_on
  network_interface_id    = azurerm_network_interface.web[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web[0].id
}

resource "azurerm_lb_probe" "web" {
  count               = var.deploy_backends ? 1 : 0
  name                = "probe-web"
  loadbalancer_id     = azurerm_lb.web[0].id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "web_http" {
  count                          = var.deploy_backends ? 1 : 0
  name                           = "http-80"
  loadbalancer_id                = azurerm_lb.web[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-web"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web[0].id]
  probe_id                       = azurerm_lb_probe.web[0].id
}
