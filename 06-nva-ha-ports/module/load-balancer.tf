resource "azurerm_lb" "lab" {
  name                = "nva-ilb"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = local.tags
  frontend_ip_configuration {
    name                          = "inside"
    subnet_id                     = azurerm_subnet.nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.frontend_ip
    private_ip_address_version    = "IPv4"
    zones                         = var.nva_zones == null ? null : ["1", "2", "3"]
  }
}
resource "azurerm_lb_backend_address_pool" "nvas" {
  name            = "nva-pool"
  loadbalancer_id = azurerm_lb.lab.id
}
resource "azurerm_network_interface_backend_address_pool_association" "nvas" {
  for_each                = local.nvas
  network_interface_id    = azurerm_network_interface.vm[each.key].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.nvas.id
}
resource "azurerm_lb_probe" "readiness" {
  name                         = "nva-readiness"
  loadbalancer_id              = azurerm_lb.lab.id
  protocol                     = "Http"
  port                         = 8008
  request_path                 = "/healthz"
  interval_in_seconds          = 5
  probe_threshold              = 2
  number_of_probes             = 2
  no_healthy_backends_behavior = "AllProbedDown"
}
resource "azurerm_lb_rule" "ha" {
  name                           = "ha-ports"
  loadbalancer_id                = azurerm_lb.lab.id
  frontend_ip_configuration_name = "inside"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.nvas.id]
  probe_id                       = azurerm_lb_probe.readiness.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  floating_ip_enabled            = true
  load_distribution              = "Default"
  disable_outbound_snat          = true
  tcp_reset_enabled              = false
  # No idle-timeout failover claim: UDR-directed HA-port TCP idle timeout unsupported.
}
