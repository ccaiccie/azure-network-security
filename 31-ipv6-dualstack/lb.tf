# Gate 2 (needs gate 1): a dual-stack Standard public load balancer in front of vm-web-1.
# Two frontends (IPv4 and IPv6), two backend pools (one per IP version), one probe and one rule per family.

locals {
  lb_on = var.deploy_vms && var.deploy_lb
}

resource "azurerm_public_ip" "lb_v4" {
  count               = local.lb_on ? 1 : 0
  name                = "${local.p}-lb-pip4"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  allocation_method   = "Static"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_public_ip" "lb_v6" {
  count               = local.lb_on ? 1 : 0
  name                = "${local.p}-lb-pip6"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  allocation_method   = "Static"
  ip_version          = "IPv6"
  tags                = local.tags
}

resource "azurerm_lb" "dual" {
  count               = local.lb_on ? 1 : 0
  name                = "${local.p}-lb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "fe-v4"
    public_ip_address_id = azurerm_public_ip.lb_v4[0].id
  }

  frontend_ip_configuration {
    name                 = "fe-v6"
    public_ip_address_id = azurerm_public_ip.lb_v6[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "v4" {
  count           = local.lb_on ? 1 : 0
  name            = "be-v4"
  loadbalancer_id = azurerm_lb.dual[0].id
}

resource "azurerm_lb_backend_address_pool" "v6" {
  count           = local.lb_on ? 1 : 0
  name            = "be-v6"
  loadbalancer_id = azurerm_lb.dual[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "v4" {
  count                   = local.lb_on ? 1 : 0
  network_interface_id    = azurerm_network_interface.vm["vm-web-1"].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.v4[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "v6" {
  count                   = local.lb_on ? 1 : 0
  network_interface_id    = azurerm_network_interface.vm["vm-web-1"].id
  ip_configuration_name   = "ipconfig2"
  backend_address_pool_id = azurerm_lb_backend_address_pool.v6[0].id
}

resource "azurerm_lb_probe" "app" {
  count           = local.lb_on ? 1 : 0
  name            = "probe-8080"
  loadbalancer_id = azurerm_lb.dual[0].id
  protocol        = "Tcp"
  port            = 8080
}

resource "azurerm_lb_rule" "v4" {
  count                          = local.lb_on ? 1 : 0
  name                           = "rule-v4-8080"
  loadbalancer_id                = azurerm_lb.dual[0].id
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "fe-v4"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.v4[0].id]
  probe_id                       = azurerm_lb_probe.app[0].id
  disable_outbound_snat          = true
}

resource "azurerm_lb_rule" "v6" {
  count                          = local.lb_on ? 1 : 0
  name                           = "rule-v6-8080"
  loadbalancer_id                = azurerm_lb.dual[0].id
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "fe-v6"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.v6[0].id]
  probe_id                       = azurerm_lb_probe.app[0].id
  disable_outbound_snat          = true
}
