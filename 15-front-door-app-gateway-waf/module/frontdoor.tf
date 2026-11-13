resource "azurerm_cdn_frontdoor_profile" "lab" {
  name                     = "layered-frontdoor"
  resource_group_name      = azurerm_resource_group.lab.name
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 30
  tags                     = local.tags
}
resource "azurerm_cdn_frontdoor_endpoint" "lab" {
  name                     = var.edge_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id
  enabled                  = true
  tags                     = local.tags
}
resource "azurerm_cdn_frontdoor_origin_group" "gateway" {
  name                     = "regional-gateway-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id
  session_affinity_enabled = false
  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
  health_probe {
    interval_in_seconds = 30
    path                = "/health"
    protocol            = "Https"
    request_type        = "HEAD"
  }
}
resource "azurerm_cdn_frontdoor_origin" "gateway" {
  name                           = "regional-gateway-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.gateway.id
  enabled                        = var.gateway_ingress_enabled
  host_name                      = var.origin_fqdn
  origin_host_header             = var.origin_fqdn
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}
resource "azurerm_cdn_frontdoor_route" "lab" {
  name                          = "owned-https-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.lab.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.gateway.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.gateway.id]
  enabled                       = var.edge_route_enabled
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = true
  # No cache block: cache is disabled. No edge ruleset overrides origin security.
  depends_on = [azurerm_cdn_frontdoor_security_policy.edge]
}
resource "azurerm_cdn_frontdoor_security_policy" "edge" {
  name                     = "owned-edge-security"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.edge.id
      association {
        patterns_to_match = ["/*"]
        domain { cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.lab.id }
      }
    }
  }
}
