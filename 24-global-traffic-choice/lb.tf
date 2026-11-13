# Gate 1 (deploy_backends), part 2: a public Standard load balancer (layer 4) in front of the two VMs.
# It is also the lab's second Traffic Manager endpoint, and it gives the VMs outbound access.

resource "azurerm_public_ip" "lb" {
  count               = var.deploy_backends ? 1 : 0
  name                = "${var.name_prefix}-lb-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.name_prefix}-lb-${random_string.suffix.result}"
  tags                = local.tags
}

resource "azurerm_lb" "web" {
  count               = var.deploy_backends ? 1 : 0
  name                = "${var.name_prefix}-lb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "fe-public"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  count           = var.deploy_backends ? 1 : 0
  name            = "pool-web"
  loadbalancer_id = azurerm_lb.web[0].id
}

# The probe is a layer 7 check here, but the load balancer only asks "does this path answer 200?". It never sees the user's request.
resource "azurerm_lb_probe" "web" {
  count               = var.deploy_backends ? 1 : 0
  name                = "probe-http"
  loadbalancer_id     = azurerm_lb.web[0].id
  protocol            = "Http"
  port                = 80
  request_path        = var.probe_path
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  count                          = var.deploy_backends ? 1 : 0
  name                           = "rule-http"
  loadbalancer_id                = azurerm_lb.web[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web[0].id]
  probe_id                       = azurerm_lb_probe.web[0].id
  disable_outbound_snat          = false
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
  count                   = var.deploy_backends ? 2 : 0
  network_interface_id    = azurerm_network_interface.web[count.index].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web[0].id
}
