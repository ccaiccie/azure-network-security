# Gate 4 (COSTS, exposes TCP 80): a public Standard load balancer on the same two VMs.
# Gate 5 (COSTS): a global (cross-region) load balancer whose backend is the public load balancer's frontend.
resource "azurerm_public_ip" "regional" {
  count               = var.create_public_lb ? 1 : 0
  name                = "pip-lb-public"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.frontend_zones
  tags                = var.tags
}

resource "azurerm_lb" "public" {
  count               = var.create_public_lb ? 1 : 0
  name                = "lb-public"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "fe-public"
    public_ip_address_id = azurerm_public_ip.regional[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "public_web" {
  count           = var.create_public_lb ? 1 : 0
  loadbalancer_id = azurerm_lb.public[0].id
  name            = "pool-web"
}

resource "azurerm_lb_probe" "public_tcp80" {
  count               = var.create_public_lb ? 1 : 0
  loadbalancer_id     = azurerm_lb.public[0].id
  name                = "probe-tcp-80"
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

# disable_outbound_snat = true: this rule is for inbound only. Outbound design is a separate topic.
resource "azurerm_lb_rule" "public_http" {
  count                          = var.create_public_lb ? 1 : 0
  loadbalancer_id                = azurerm_lb.public[0].id
  name                           = "rule-http-80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.public_web[0].id]
  probe_id                       = azurerm_lb_probe.public_tcp80[0].id
  disable_outbound_snat          = true
}

# A NIC can sit in the pool of one public and one internal load balancer at the same time.
resource "azurerm_network_interface_backend_address_pool_association" "public_web" {
  for_each                = var.create_public_lb ? local.web_vms : {}
  network_interface_id    = azurerm_network_interface.web[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.public_web[0].id
}

# ------------------------------------------------------------------ global tier
resource "azurerm_public_ip" "global" {
  count               = var.create_global_lb ? 1 : 0
  name                = "pip-lb-global"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Global"
  tags                = var.tags
}

resource "azurerm_lb" "global" {
  count               = var.create_global_lb ? 1 : 0
  name                = "lb-global"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  sku_tier            = "Global"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "fe-global"
    public_ip_address_id = azurerm_public_ip.global[0].id
  }

  lifecycle {
    precondition {
      condition     = var.create_public_lb
      error_message = "create_global_lb needs create_public_lb: the global backend is a regional public frontend."
    }
  }
}

resource "azurerm_lb_backend_address_pool" "global" {
  count           = var.create_global_lb ? 1 : 0
  loadbalancer_id = azurerm_lb.global[0].id
  name            = "pool-regions"
}

# The global pool member is the regional load balancer's frontend IP configuration.
resource "azurerm_lb_backend_address_pool_address" "region1" {
  count                               = var.create_global_lb ? 1 : 0
  name                                = "region1-lb-public"
  backend_address_pool_id             = azurerm_lb_backend_address_pool.global[0].id
  backend_address_ip_configuration_id = azurerm_lb.public[0].frontend_ip_configuration[0].id
}

resource "azurerm_lb_rule" "global_http" {
  count                          = var.create_global_lb ? 1 : 0
  loadbalancer_id                = azurerm_lb.global[0].id
  name                           = "rule-http-80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-global"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.global[0].id]
}
