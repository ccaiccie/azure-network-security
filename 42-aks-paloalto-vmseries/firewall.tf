# Gate 1: two VM-Series VMs (management, untrust, trust NICs), the internal Standard load balancer with an HA ports
# rule and a TCP probe, and the public IPs. This stage is costly. The Marketplace terms must be accepted first.

locals {
  fws = {
    fw1 = { index = 1, mgmt = "10.70.0.4", untrust = "10.70.1.4", trust = "10.70.2.4" }
    fw2 = { index = 2, mgmt = "10.70.0.5", untrust = "10.70.1.5", trust = "10.70.2.5" }
  }
  fw_on = var.deploy_firewalls ? local.fws : {}
}

# Accepting Marketplace terms is a legal step on your subscription. Review the terms and price first.
resource "azurerm_marketplace_agreement" "vmseries" {
  count     = var.deploy_firewalls && var.accept_marketplace_terms ? 1 : 0
  publisher = var.vmseries_publisher
  offer     = var.vmseries_offer
  plan      = var.vmseries_sku
}

resource "azurerm_availability_set" "fw" {
  count               = var.deploy_firewalls && !var.use_availability_zones ? 1 : 0
  name                = "${local.p}-fw-avset"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_public_ip" "mgmt" {
  for_each            = local.fw_on
  name                = "${local.p}-${each.key}-mgmt-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_public_ip" "untrust" {
  for_each            = local.fw_on
  name                = "${local.p}-${each.key}-untrust-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "mgmt" {
  for_each            = local.fw_on
  name                = "${local.p}-${each.key}-nic-mgmt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.mgmt
    public_ip_address_id          = azurerm_public_ip.mgmt[each.key].id
  }
}

resource "azurerm_network_interface" "untrust" {
  for_each              = local.fw_on
  name                  = "${local.p}-${each.key}-nic-untrust"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.untrust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.untrust
    public_ip_address_id          = azurerm_public_ip.untrust[each.key].id
  }
}

resource "azurerm_network_interface" "trust" {
  for_each              = local.fw_on
  name                  = "${local.p}-${each.key}-nic-trust"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.trust
  }
}

resource "azurerm_linux_virtual_machine" "fw" {
  for_each                        = local.fw_on
  name                            = "${local.p}-${each.key}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vmseries_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  availability_set_id             = var.use_availability_zones ? null : azurerm_availability_set.fw[0].id
  zone                            = var.use_availability_zones ? tostring(each.value.index) : null
  tags                            = local.tags

  # The first NIC is the primary NIC and becomes the PAN-OS management interface (eth0).
  network_interface_ids = [
    azurerm_network_interface.mgmt[each.key].id,
    azurerm_network_interface.untrust[each.key].id,
    azurerm_network_interface.trust[each.key].id,
  ]

  # Bootstrap: user data that points at a bootstrap package. Empty means configure by hand.
  custom_data = var.bootstrap_storage_account == "" ? null : base64encode(join("\n", [
    "storage-account=${var.bootstrap_storage_account}",
    "access-key=${var.bootstrap_access_key}",
    "file-share=${var.bootstrap_file_share}",
    "share-directory=${var.bootstrap_share_directory}",
  ]))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.vmseries_publisher
    offer     = var.vmseries_offer
    sku       = var.vmseries_sku
    version   = var.vmseries_version
  }

  plan {
    name      = var.vmseries_sku
    product   = var.vmseries_offer
    publisher = var.vmseries_publisher
  }

  lifecycle {
    precondition {
      condition     = var.admin_password != null
      error_message = "Set admin_password through TF_VAR_admin_password or your secret store."
    }
  }

  depends_on = [azurerm_marketplace_agreement.vmseries]
}

# ---------------------------------------------------------------- internal load balancer with HA ports

resource "azurerm_lb" "ilb" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "${local.p}-ilb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                          = "fe-trust"
    subnet_id                     = azurerm_subnet.trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ilb_frontend_ip
  }
}

resource "azurerm_lb_backend_address_pool" "fw" {
  count           = var.deploy_firewalls ? 1 : 0
  name            = "fw-trust"
  loadbalancer_id = azurerm_lb.ilb[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "trust" {
  for_each                = local.fw_on
  network_interface_id    = azurerm_network_interface.trust[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.fw[0].id
}

# The probe comes from 168.63.129.16 to the trust NIC. The firewall must answer on this port (interface management
# profile), the trust NSG must allow AzureLoadBalancer, and the virtual router needs a route for 168.63.129.16/32.
resource "azurerm_lb_probe" "fw" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "probe-tcp-443"
  loadbalancer_id     = azurerm_lb.ilb[0].id
  protocol            = "Tcp"
  port                = 443
  interval_in_seconds = 5
}

# HA ports: protocol All and port 0 on both sides. The packet's destination is not the frontend IP, so it is passed on unchanged.
resource "azurerm_lb_rule" "ha_ports" {
  count                          = var.deploy_firewalls ? 1 : 0
  name                           = "ha-ports"
  loadbalancer_id                = azurerm_lb.ilb[0].id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "fe-trust"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.fw[0].id]
  probe_id                       = azurerm_lb_probe.fw[0].id
  floating_ip_enabled            = false
}
