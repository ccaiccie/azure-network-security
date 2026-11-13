resource "azurerm_lb" "inspection" {
  name                = "inspection-gwlb"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Gateway"
  sku_tier            = "Regional"
  tags                = local.tags
  frontend_ip_configuration {
    name                          = "inspection-frontend"
    subnet_id                     = azurerm_subnet.frontend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.gwlb_ip
  }
}
resource "azurerm_lb_backend_address_pool" "nvas" {
  name            = "nva-pool"
  loadbalancer_id = azurerm_lb.inspection.id
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
resource "azurerm_network_interface_backend_address_pool_association" "nvas" {
  for_each                = toset(["nva1", "nva2"])
  network_interface_id    = azurerm_network_interface.vm[each.key].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.nvas.id
}
resource "azurerm_lb_probe" "nva" {
  name                         = "nva-readiness"
  loadbalancer_id              = azurerm_lb.inspection.id
  protocol                     = "Http"
  port                         = 8008
  request_path                 = "/health"
  interval_in_seconds          = 5
  number_of_probes             = 2
  probe_threshold              = 2
  no_healthy_backends_behavior = "AllProbedDown"
}
resource "azurerm_lb_rule" "inspection" {
  name                           = "ha-ports"
  loadbalancer_id                = azurerm_lb.inspection.id
  frontend_ip_configuration_name = "inspection-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.nvas.id]
  probe_id                       = azurerm_lb_probe.nva.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  floating_ip_enabled            = false
  disable_outbound_snat          = true
  load_distribution              = "Default"
  tcp_reset_enabled              = false
  idle_timeout_in_minutes        = 4
}
resource "azurerm_public_ip" "consumer" {
  name                = "consumer-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  ip_version          = "IPv4"
  tags                = local.tags
  lifecycle {
    postcondition {
      condition     = self.ip_address != var.client_public_ip
      error_message = "External client must differ from owned consumer public endpoint."
    }
  }
}
resource "azurerm_lb" "consumer" {
  name                = "public-lb"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = local.tags
  frontend_ip_configuration {
    name                                               = "public-frontend"
    public_ip_address_id                               = azurerm_public_ip.consumer.id
    gateway_load_balancer_frontend_ip_configuration_id = var.enable_chain ? one(azurerm_lb.inspection.frontend_ip_configuration).id : null
  }
}
resource "azurerm_lb_backend_address_pool" "app" {
  name            = "app-pool"
  loadbalancer_id = azurerm_lb.consumer.id
}
resource "azurerm_network_interface_backend_address_pool_association" "app" {
  network_interface_id    = azurerm_network_interface.vm["app"].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id
}
resource "azurerm_lb_probe" "app" {
  name                         = "app-readiness"
  loadbalancer_id              = azurerm_lb.consumer.id
  protocol                     = "Http"
  port                         = 8009
  request_path                 = "/health"
  interval_in_seconds          = 5
  number_of_probes             = 2
  probe_threshold              = 2
  no_healthy_backends_behavior = "AllProbedDown"
}
resource "azurerm_lb_rule" "app" {
  for_each                       = toset(["8080", "8081"])
  name                           = "http-${each.key}"
  loadbalancer_id                = azurerm_lb.consumer.id
  frontend_ip_configuration_name = "public-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.app.id
  protocol                       = "Tcp"
  frontend_port                  = tonumber(each.key)
  backend_port                   = tonumber(each.key)
  floating_ip_enabled            = false
  disable_outbound_snat          = true
  load_distribution              = "Default"
  tcp_reset_enabled              = true
  idle_timeout_in_minutes        = 4
}
# Inbound-only companion: no outbound rules, public VM NICs or NAT gateway.
