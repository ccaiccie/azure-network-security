# Gate 2 (deploy_app_gateway): Application Gateway Standard_v2 (layer 7, regional) in front of the same two VMs.
# It bills by the hour plus capacity units; check current pricing. It also adds a response header with a rewrite rule.

resource "azurerm_public_ip" "agw" {
  count               = var.deploy_app_gateway ? 1 : 0
  name                = "${var.name_prefix}-agw-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.name_prefix}-agw-${random_string.suffix.result}"
  tags                = local.tags
}

locals {
  agw_name = "${var.name_prefix}-agw"
}

resource "azurerm_application_gateway" "web" {
  count               = var.deploy_app_gateway ? 1 : 0
  name                = local.agw_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = var.appgw_min_capacity
    max_capacity = var.appgw_max_capacity
  }

  gateway_ip_configuration {
    name      = "gwip"
    subnet_id = azurerm_subnet.agw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "fe-public"
    public_ip_address_id = azurerm_public_ip.agw[0].id
  }

  backend_address_pool {
    name         = "pool-web"
    ip_addresses = local.web_ips
  }

  probe {
    name                                      = "probe-web"
    protocol                                  = "Http"
    path                                      = var.appgw_probe_path
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                                = "bhs-http-80"
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 30
    probe_name                          = "probe-web"
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "fe-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  rewrite_rule_set {
    name = "rewrite-tier"

    rewrite_rule {
      name          = "add-tier-header"
      rule_sequence = 100

      response_header_configuration {
        header_name  = "X-Lab-Tier"
        header_value = "application-gateway"
      }
    }
  }

  request_routing_rule {
    name                       = "rule-basic"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "listener-http"
    backend_address_pool_name  = "pool-web"
    backend_http_settings_name = "bhs-http-80"
    rewrite_rule_set_name      = "rewrite-tier"
  }

  depends_on = [azurerm_subnet_network_security_group_association.agw]
}
