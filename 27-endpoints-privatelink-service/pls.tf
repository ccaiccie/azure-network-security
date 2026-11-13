# Gate 5 (deploy_pls): the provider side and a consumer endpoint.
#   vm-backend-1 (vms.tf) -> Standard internal load balancer 10.60.1.100:8080 -> Private Link Service
#   NAT IPs come from snet-pls. The consumer reaches it through pe-pls (10.50.2.6) in snet-pe, using the alias.
#   break_fix = pls_pending  leaves the auto-approval list empty, so the consumer request waits for approval
#   enable_proxy_protocol    adds the PROXY protocol v2 header; pls_nat_ip_count adds NAT IPs

resource "azurerm_lb" "ilb" {
  count               = var.deploy_pls ? 1 : 0
  name                = "${var.name_prefix}-ilb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                          = "fe1"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.1.100"
  }
}

resource "azurerm_lb_backend_address_pool" "pool" {
  count           = var.deploy_pls ? 1 : 0
  name            = "pool1"
  loadbalancer_id = azurerm_lb.ilb[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "backend" {
  count                   = var.deploy_pls ? 1 : 0
  network_interface_id    = azurerm_network_interface.vm["vm-backend-1"].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.pool[0].id
}

resource "azurerm_lb_probe" "tcp8080" {
  count           = var.deploy_pls ? 1 : 0
  name            = "tcp-8080"
  loadbalancer_id = azurerm_lb.ilb[0].id
  protocol        = "Tcp"
  port            = 8080
}

resource "azurerm_lb_rule" "svc" {
  count                          = var.deploy_pls ? 1 : 0
  name                           = "svc-8080"
  loadbalancer_id                = azurerm_lb.ilb[0].id
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "fe1"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pool[0].id]
  probe_id                       = azurerm_lb_probe.tcp8080[0].id
}

resource "azurerm_private_link_service" "svc" {
  count                                       = var.deploy_pls ? 1 : 0
  name                                        = "${var.name_prefix}-pls"
  location                                    = azurerm_resource_group.lab.location
  resource_group_name                         = azurerm_resource_group.lab.name
  load_balancer_frontend_ip_configuration_ids = [azurerm_lb.ilb[0].frontend_ip_configuration[0].id]
  enable_proxy_protocol                       = var.enable_proxy_protocol
  visibility_subscription_ids                 = [var.subscription_id]
  auto_approval_subscription_ids              = var.break_fix == "pls_pending" ? [] : [var.subscription_id]
  tags                                        = local.tags

  # One NAT IP configuration per requested address. The first one is the primary.
  dynamic "nat_ip_configuration" {
    for_each = range(var.pls_nat_ip_count)
    content {
      name                       = "nat-${nat_ip_configuration.value + 1}"
      primary                    = nat_ip_configuration.value == 0
      private_ip_address         = cidrhost("10.60.2.0/28", 4 + nat_ip_configuration.value)
      private_ip_address_version = "IPv4"
      subnet_id                  = azurerm_subnet.pls.id
    }
  }
}

# The consumer connects by alias, which is always a manual-type request: the provider's auto-approval list decides.
resource "azurerm_private_endpoint" "pls" {
  count               = var.deploy_pls ? 1 : 0
  name                = "${var.name_prefix}-pe-pls"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.tags

  ip_configuration {
    name               = "pls"
    private_ip_address = "10.50.2.6"
  }

  private_service_connection {
    name                              = "to-pls"
    private_connection_resource_alias = azurerm_private_link_service.svc[0].alias
    is_manual_connection              = true
    request_message                   = "Lab consumer request"
  }
}
