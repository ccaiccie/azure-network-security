# Gate 3 (deploy_lb_outbound): an outbound-only public Standard load balancer for vm-lb.
# There are no load balancing rules, so nothing can arrive through it: it exists only for SNAT.

resource "azurerm_public_ip" "lb" {
  count               = var.deploy_lb_outbound ? 1 : 0
  name                = "${var.name_prefix}-lb-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_lb" "lab" {
  count               = var.deploy_lb_outbound ? 1 : 0
  name                = "${var.name_prefix}-lb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "fe-outbound"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "lab" {
  count           = var.deploy_lb_outbound ? 1 : 0
  name            = "pool-outbound"
  loadbalancer_id = azurerm_lb.lab[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "lb" {
  count                   = var.deploy_lb_outbound && var.deploy_vms ? 1 : 0
  network_interface_id    = azurerm_network_interface.lb[0].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lab[0].id
}

resource "azurerm_lb_outbound_rule" "lab" {
  count                    = var.deploy_lb_outbound ? 1 : 0
  name                     = "outbound-all"
  loadbalancer_id          = azurerm_lb.lab[0].id
  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.lab[0].id
  allocated_outbound_ports = var.lb_allocated_ports
  idle_timeout_in_minutes  = var.lb_idle_timeout_minutes
  enable_tcp_reset         = true

  frontend_ip_configuration {
    name = "fe-outbound"
  }
}
