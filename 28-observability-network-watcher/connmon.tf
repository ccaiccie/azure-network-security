# Gate 4 (deploy_connection_monitor): one Connection Monitor, source vm-client, destination vm-server.
# The monitor needs the Network Watcher agent extension on the source VM (vms.tf). Results go to the workspace.
# monitor_protocol and monitor_rtt_threshold_ms are the switches for break/fix 4.

locals {
  cm_on = var.deploy_connection_monitor && var.deploy_vms && var.deploy_monitoring
}

resource "azurerm_network_connection_monitor" "lab" {
  count              = local.cm_on ? 1 : 0
  name               = "${var.name_prefix}-cm"
  network_watcher_id = local.watcher_id
  location           = azurerm_resource_group.lab.location
  tags               = local.tags

  endpoint {
    name               = "vm-client"
    target_resource_id = azurerm_linux_virtual_machine.vm["client"].id
  }

  endpoint {
    name    = "vm-server"
    address = "10.81.0.10"
  }

  test_configuration {
    name                      = "app-check"
    protocol                  = var.monitor_protocol
    test_frequency_in_seconds = 30

    dynamic "tcp_configuration" {
      for_each = var.monitor_protocol == "Tcp" ? [1] : []
      content {
        port = var.app_port
      }
    }

    dynamic "icmp_configuration" {
      for_each = var.monitor_protocol == "Icmp" ? [1] : []
      content {
        trace_route_enabled = false
      }
    }

    success_threshold {
      checks_failed_percent = 20
      round_trip_time_ms    = var.monitor_rtt_threshold_ms
    }
  }

  test_group {
    name                     = "client-to-server"
    destination_endpoints    = ["vm-server"]
    source_endpoints         = ["vm-client"]
    test_configuration_names = ["app-check"]
  }

  notes = "Lab Connection Monitor. Designed, not tested."

  output_workspace_resource_ids = [azurerm_log_analytics_workspace.lab[0].id]

  depends_on = [azurerm_virtual_machine_extension.watcher_agent]
}
