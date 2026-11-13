# Gate 3 (deploy_front_door): Azure Front Door Standard in front of the Application Gateway.
# Front Door is global and has no VNet; its origin is the Application Gateway's public name.

resource "azurerm_cdn_frontdoor_profile" "lab" {
  count               = var.deploy_front_door ? 1 : 0
  name                = "${var.name_prefix}-afd"
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "lab" {
  count                    = var.deploy_front_door ? 1 : 0
  name                     = "${var.name_prefix}-ep-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab[0].id
  tags                     = local.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "appgw" {
  count                    = var.deploy_front_door ? 1 : 0
  name                     = "og-appgw"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab[0].id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    protocol            = "Http"
    request_type        = "GET"
    path                = var.probe_path
    interval_in_seconds = 30
  }
}

resource "azurerm_cdn_frontdoor_origin" "appgw" {
  count                          = var.deploy_front_door ? 1 : 0
  name                           = "origin-appgw"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.appgw[0].id
  enabled                        = true
  host_name                      = azurerm_public_ip.agw[0].fqdn
  origin_host_header             = azurerm_public_ip.agw[0].fqdn
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_route" "default" {
  count                         = var.deploy_front_door ? 1 : 0
  name                          = "route-default"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.lab[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.appgw[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.appgw[0].id]
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  forwarding_protocol           = "HttpOnly"
  https_redirect_enabled        = false
  link_to_default_domain        = true
}
