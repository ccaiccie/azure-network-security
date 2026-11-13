resource "azurerm_service_plan" "backend" {
  name                = "waf-backend-plan"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.tags
}
resource "azurerm_linux_web_app" "backend" {
  name                                           = var.backend_name
  resource_group_name                            = azurerm_resource_group.lab.name
  location                                       = azurerm_resource_group.lab.location
  service_plan_id                                = azurerm_service_plan.backend.id
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags
  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE       = "1"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false"
  }
  site_config {
    always_on                = true
    app_command_line         = "node /home/site/wwwroot/server.js"
    ftps_state               = "Disabled"
    minimum_tls_version      = "1.2"
    scm_minimum_tls_version  = "1.2"
    http2_enabled            = false
    remote_debugging_enabled = false
    application_stack { node_version = "24-lts" }
    ip_restriction_default_action = "Deny"
    dynamic "ip_restriction" {
      for_each = var.backend_access_enabled ? [1] : []
      content {
        name       = "only-owned-gateway"
        priority   = 100
        action     = "Allow"
        ip_address = "${azurerm_public_ip.gateway.ip_address}/32"
      }
    }
    scm_use_main_ip_restriction       = false
    scm_ip_restriction_default_action = "Deny"
    dynamic "scm_ip_restriction" {
      for_each = var.fixture_publish_enabled ? [1] : []
      content {
        name       = "approved-publisher"
        priority   = 100
        action     = "Allow"
        ip_address = var.operator_cidr
      }
    }
  }
  logs {
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 25
      }
    }
  }
  # No publishing-credential read, zip_deploy_file, local-exec or key material.
}
