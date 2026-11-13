# Gate 2: diagnostics, a workspace, an action group and a metric alert. Needs gate 1.
# Metric and log category names are written from documentation knowledge: check the
# metric definitions on your own public IP and the current Microsoft docs.

locals {
  mon_on = var.deploy_monitoring && var.deploy_workload
}

resource "azurerm_log_analytics_workspace" "lab" {
  count               = local.mon_on ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "lab" {
  count               = local.mon_on ? 1 : 0
  name                = "${var.name_prefix}-ag"
  resource_group_name = azurerm_resource_group.lab.name
  short_name          = "ddosag"
  tags                = local.tags

  email_receiver {
    name                    = "oncall"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Diagnostic setting on the public IP resource: the DDoS logs only exist if this is here.
resource "azurerm_monitor_diagnostic_setting" "pip_web" {
  count                      = local.mon_on ? 1 : 0
  name                       = "diag-pip-web"
  target_resource_id         = azurerm_public_ip.web[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab[0].id

  enabled_log {
    category = "DDoSProtectionNotifications"
  }

  enabled_log {
    category = "DDoSMitigationFlowLogs"
  }

  enabled_log {
    category = "DDoSMitigationReports"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# The scope must be the protected public IP: the metric lives on it.
resource "azurerm_monitor_metric_alert" "under_attack" {
  count               = local.mon_on ? 1 : 0
  name                = "${var.name_prefix}-under-attack"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [var.alert_on_spare_ip_by_mistake ? azurerm_public_ip.spare[0].id : azurerm_public_ip.web[0].id]
  description         = "Fires while DDoS mitigation is active on the public IP."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Network/publicIPAddresses"
    metric_name      = "IfUnderDDoSAttack"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.lab[0].id
  }
}
