# Gate 7: monitoring that exists before the first circuit does.
# Metric names and namespaces were written from documentation knowledge: check them against current docs.

resource "azurerm_log_analytics_workspace" "mon" {
  count               = var.deploy_alerts ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "ops" {
  count               = var.deploy_alerts ? 1 : 0
  name                = "${var.name_prefix}-ag"
  resource_group_name = azurerm_resource_group.lab.name
  short_name          = "er34ops"

  email_receiver {
    name          = "ops"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_diagnostic_setting" "gateway" {
  count                      = var.deploy_alerts && var.deploy_er_gateway ? 1 : 0
  name                       = "metrics-to-law"
  target_resource_id         = azurerm_virtual_network_gateway.er[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.mon[0].id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "gateway_cpu" {
  count               = var.deploy_alerts && var.deploy_er_gateway ? 1 : 0
  name                = "${var.name_prefix}-gw-cpu"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [azurerm_virtual_network_gateway.er[0].id]
  description         = "ExpressRoute gateway CPU above 80 percent for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Network/virtualNetworkGateways"
    metric_name      = "ExpressRouteGatewayCpuUtilization"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops[0].id
  }
}

# Circuit alerts exist only when a circuit id is known (gate 2, gate 4 or existing_circuit_id).
resource "azurerm_monitor_metric_alert" "bgp_availability" {
  count               = var.deploy_alerts && local.circuit_id != "" ? 1 : 0
  name                = "${var.name_prefix}-bgp-availability"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [local.circuit_id]
  description         = "BGP availability below 100 percent on any path."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Network/expressRouteCircuits"
    metric_name      = "BgpAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100

    dimension {
      name     = "PeeringType"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops[0].id
  }
}

resource "azurerm_monitor_metric_alert" "arp_availability" {
  count               = var.deploy_alerts && local.circuit_id != "" ? 1 : 0
  name                = "${var.name_prefix}-arp-availability"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [local.circuit_id]
  description         = "ARP availability below 100 percent on any path."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Network/expressRouteCircuits"
    metric_name      = "ArpAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops[0].id
  }
}
