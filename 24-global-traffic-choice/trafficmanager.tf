# Gate 4 (deploy_traffic_manager): a Traffic Manager profile (DNS-based). It never carries user traffic.
# Endpoint 1 is the Application Gateway name (priority 1), endpoint 2 is the load balancer name (priority 2).

resource "azurerm_traffic_manager_profile" "lab" {
  count                  = var.deploy_traffic_manager ? 1 : 0
  name                   = "${var.name_prefix}-tm"
  resource_group_name    = azurerm_resource_group.lab.name
  traffic_routing_method = var.tm_routing_method
  tags                   = local.tags

  dns_config {
    relative_name = "${var.name_prefix}-tm-${random_string.suffix.result}"
    ttl           = var.tm_ttl_seconds
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = var.probe_path
    interval_in_seconds          = var.tm_probe_interval_seconds
    timeout_in_seconds           = var.tm_probe_interval_seconds == 10 ? 9 : 10
    tolerated_number_of_failures = var.tm_tolerated_failures
  }
}

resource "azurerm_traffic_manager_external_endpoint" "agw" {
  count      = var.deploy_traffic_manager ? 1 : 0
  name       = "ep-appgw"
  profile_id = azurerm_traffic_manager_profile.lab[0].id
  target     = azurerm_public_ip.agw[0].fqdn
  priority   = 1
  weight     = 100
}

resource "azurerm_traffic_manager_external_endpoint" "lb" {
  count      = var.deploy_traffic_manager ? 1 : 0
  name       = "ep-lb"
  profile_id = azurerm_traffic_manager_profile.lab[0].id
  target     = azurerm_public_ip.lb[0].fqdn
  priority   = 2
  weight     = 100
}
