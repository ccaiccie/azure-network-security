# Gate 1: two VM-Series VMs. Each has a management, an untrust and a trust NIC, plus a fourth NIC for the Gateway LB
# variant (gate 3). This stage is costly. The Marketplace terms must be accepted first.

locals {
  fws = {
    fw1 = { index = 1, mgmt = "10.80.0.4", untrust = "10.80.1.4", trust = "10.80.2.4", gw = "10.80.3.4" }
    fw2 = { index = 2, mgmt = "10.80.0.5", untrust = "10.80.1.5", trust = "10.80.2.5", gw = "10.80.3.5" }
  }
  fw_on = var.deploy_firewalls ? local.fws : {}
  gw_on = var.deploy_firewalls && var.deploy_gateway_lb ? local.fws : {}
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

# IP forwarding is required on every data NIC: the firewall handles packets that are not addressed to it.
resource "azurerm_network_interface" "untrust" {
  for_each                       = local.fw_on
  name                           = "${local.p}-${each.key}-nic-untrust"
  location                       = azurerm_resource_group.lab.location
  resource_group_name            = azurerm_resource_group.lab.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = var.enable_accelerated_networking
  tags                           = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.untrust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.untrust
  }
}

resource "azurerm_network_interface" "trust" {
  for_each                       = local.fw_on
  name                           = "${local.p}-${each.key}-nic-trust"
  location                       = azurerm_resource_group.lab.location
  resource_group_name            = azurerm_resource_group.lab.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = var.enable_accelerated_networking
  tags                           = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.trust
  }
}

resource "azurerm_network_interface" "gw" {
  for_each                       = local.gw_on
  name                           = "${local.p}-${each.key}-nic-gw"
  location                       = azurerm_resource_group.lab.location
  resource_group_name            = azurerm_resource_group.lab.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = var.enable_accelerated_networking
  tags                           = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.gwlb.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.gw
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

  # The first NIC is the primary NIC and becomes the PAN-OS management interface (eth0). The order of the others
  # maps to ethernet1/1, ethernet1/2 and ethernet1/3 in PAN-OS.
  network_interface_ids = concat(
    [
      azurerm_network_interface.mgmt[each.key].id,
      azurerm_network_interface.untrust[each.key].id,
      azurerm_network_interface.trust[each.key].id,
    ],
    var.deploy_gateway_lb ? [azurerm_network_interface.gw[each.key].id] : []
  )

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
