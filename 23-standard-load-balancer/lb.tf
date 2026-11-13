# The internal Standard load balancer: one frontend, one pool, one probe, one rule. Free-ish: no VMs are needed to create it.
resource "azurerm_lb" "internal" {
  name                = "lb-internal"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "fe-web"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.frontend_ip
    zones                         = var.frontend_zones
  }

  dynamic "frontend_ip_configuration" {
    for_each = var.enable_ha_ports_rule ? [1] : []
    content {
      name                          = "fe-ha"
      subnet_id                     = azurerm_subnet.web.id
      private_ip_address_allocation = "Static"
      private_ip_address            = local.ha_frontend_ip
      zones                         = var.frontend_zones
    }
  }
}

# NIC-based backend pool: members are added by the NIC association in vms.tf.
resource "azurerm_lb_backend_address_pool" "web" {
  loadbalancer_id = azurerm_lb.internal.id
  name            = "pool-web"
}

# TCP probe every 5 seconds; two failed probes in a row mark an instance down (check current docs for defaults and for
# the provider argument that replaced number_of_probes).
resource "azurerm_lb_probe" "tcp80" {
  loadbalancer_id     = azurerm_lb.internal.id
  name                = "probe-tcp-80"
  protocol            = "Tcp"
  port                = local.probe_port
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_probe" "http_health" {
  loadbalancer_id     = azurerm_lb.internal.id
  name                = "probe-http-health"
  protocol            = "Http"
  port                = 8080
  request_path        = "/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "rule-http-80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-web"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.tcp80.id
  load_distribution              = local.distribution
  floating_ip_enabled            = var.floating_ip
  idle_timeout_in_minutes        = 4
  tcp_reset_enabled              = true
}

# HA ports: protocol All, ports 0 and 0, on its own frontend. An internal Standard load balancer only (check current docs).
resource "azurerm_lb_rule" "ha_ports" {
  count                          = var.enable_ha_ports_rule ? 1 : 0
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "rule-ha-ports"
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "fe-ha"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.tcp80.id
}

# Inbound NAT rule: frontend TCP 2201 to vm-web1 port 22 (one rule per VM, tied to the NIC).
resource "azurerm_lb_nat_rule" "ssh_web1" {
  count                          = var.create_nat_rule ? 1 : 0
  resource_group_name            = azurerm_resource_group.lab.name
  loadbalancer_id                = azurerm_lb.internal.id
  name                           = "nat-ssh-web1"
  protocol                       = "Tcp"
  frontend_port                  = 2201
  backend_port                   = 22
  frontend_ip_configuration_name = "fe-web"
}
