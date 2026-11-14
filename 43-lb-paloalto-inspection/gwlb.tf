# Gate 3: the Gateway Load Balancer variant. A second public frontend is chained to a Gateway Load Balancer whose
# backend pool is the fourth NIC of each firewall. Attribute names and the tunnel defaults must be checked against the
# current provider and Microsoft documentation. Needs gates 1 and 2.

locals {
  gw_enabled = var.deploy_firewalls && var.deploy_gateway_lb
}

resource "azurerm_lb" "gateway" {
  count               = local.gw_enabled ? 1 : 0
  name                = "${local.p}-gwlb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Gateway"
  tags                = local.tags

  frontend_ip_configuration {
    name                          = "fe-gw"
    subnet_id                     = azurerm_subnet.gwlb.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.gwlb_frontend_ip
  }
}

# Tunnel interfaces: the firewall must use the same UDP ports and identifiers.
resource "azurerm_lb_backend_address_pool" "gw" {
  count           = local.gw_enabled ? 1 : 0
  name            = "fw-gw"
  loadbalancer_id = azurerm_lb.gateway[0].id

  tunnel_interface {
    identifier = 800
    type       = "Internal"
    protocol   = "VXLAN"
    port       = 10800
  }

  tunnel_interface {
    identifier = 801
    type       = "External"
    protocol   = "VXLAN"
    port       = 10801
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "gw" {
  for_each                = local.gw_on
  network_interface_id    = azurerm_network_interface.gw[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.gw[0].id
}

resource "azurerm_lb_probe" "gw" {
  count               = local.gw_enabled ? 1 : 0
  name                = "probe-gw"
  loadbalancer_id     = azurerm_lb.gateway[0].id
  protocol            = "Tcp"
  port                = var.probe_port
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "gw" {
  count                          = local.gw_enabled ? 1 : 0
  name                           = "all-traffic"
  loadbalancer_id                = azurerm_lb.gateway[0].id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "fe-gw"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.gw[0].id]
  probe_id                       = azurerm_lb_probe.gw[0].id
}

# The second public load balancer: its frontend is chained to the gateway, its backend pool is the web VMs.
resource "azurerm_public_ip" "gw_web" {
  count               = local.gw_enabled ? 1 : 0
  name                = "${local.p}-gwweb-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_lb" "gw_web" {
  count               = local.gw_enabled ? 1 : 0
  name                = "${local.p}-plb-gw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                                               = "fe-gw-web"
    public_ip_address_id                               = azurerm_public_ip.gw_web[0].id
    gateway_load_balancer_frontend_ip_configuration_id = azurerm_lb.gateway[0].frontend_ip_configuration[0].id
  }

  lifecycle {
    precondition {
      condition     = var.deploy_backends
      error_message = "The Gateway LB variant needs deploy_backends = true."
    }
  }
}

resource "azurerm_lb_backend_address_pool" "gw_web" {
  count           = local.gw_enabled ? 1 : 0
  name            = "web-vms"
  loadbalancer_id = azurerm_lb.gw_web[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "gw_web" {
  for_each                = local.gw_enabled ? local.web_on : {}
  network_interface_id    = azurerm_network_interface.web[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.gw_web[0].id
}

resource "azurerm_lb_probe" "gw_web" {
  count               = local.gw_enabled ? 1 : 0
  name                = "probe-web"
  loadbalancer_id     = azurerm_lb.gw_web[0].id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "gw_web" {
  count                          = local.gw_enabled ? 1 : 0
  name                           = "http-80"
  loadbalancer_id                = azurerm_lb.gw_web[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-gw-web"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.gw_web[0].id]
  probe_id                       = azurerm_lb_probe.gw_web[0].id
  disable_outbound_snat          = true
}
