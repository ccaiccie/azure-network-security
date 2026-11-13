resource "azurerm_application_gateway" "lab" {
  name                = "regional-gateway"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  http2_enabled      = false
  firewall_policy_id = azurerm_web_application_firewall_policy.gateway.id
  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_identity_id]
  }
  gateway_ip_configuration {
    name      = "gateway-subnet"
    subnet_id = azurerm_subnet.gateway.id
  }
  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.gateway.id
  }
  frontend_port {
    name = "https"
    port = 443
  }
  ssl_certificate {
    name                = "approved-origin-certificate"
    key_vault_secret_id = var.listener_key_vault_secret_id
  }
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }
  http_listener {
    name                           = "origin-https"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "https"
    protocol                       = "Https"
    host_name                      = var.origin_fqdn
    require_sni                    = true
    ssl_certificate_name           = "approved-origin-certificate"
  }
  backend_address_pool {
    name  = "owned-backend"
    fqdns = [azurerm_linux_web_app.backend.default_hostname]
  }
  backend_http_settings {
    name                                = "backend-https"
    cookie_based_affinity               = "Disabled"
    protocol                            = "Https"
    port                                = 443
    request_timeout                     = 20
    host_name                           = azurerm_linux_web_app.backend.default_hostname
    pick_host_name_from_backend_address = false
    probe_name                          = "backend-health"
  }
  probe {
    name                                      = "backend-health"
    protocol                                  = "Https"
    host                                      = azurerm_linux_web_app.backend.default_hostname
    path                                      = "/health"
    port                                      = 443
    interval                                  = 30
    timeout                                   = 10
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    match { status_code = ["200"] }
  }
  request_routing_rule {
    name                       = "owned-backend-rule"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "origin-https"
    backend_address_pool_name  = "owned-backend"
    backend_http_settings_name = "backend-https"
  }
  depends_on = [azurerm_subnet_network_security_group_association.gateway]
}
