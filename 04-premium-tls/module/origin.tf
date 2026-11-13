# Included controlled public origin. TLS terminates at the App Service frontend,
# which uses its Azure-managed default-hostname certificate. Node sees platform HTTP.
resource "azurerm_service_plan" "origin" {
  name                = "tls-origin-plan"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.tags
}
resource "azurerm_linux_web_app" "origin" {
  name                                           = var.origin_name
  resource_group_name                            = azurerm_resource_group.lab.name
  location                                       = azurerm_resource_group.lab.location
  service_plan_id                                = azurerm_service_plan.origin.id
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  client_certificate_enabled                     = false
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
    ip_restriction {
      name       = "allow-lab-firewall"
      priority   = 100
      action     = "Allow"
      ip_address = "${azurerm_public_ip.firewall.ip_address}/32"
    }
    ip_restriction {
      name       = "allow-approved-preflight"
      priority   = 110
      action     = "Allow"
      ip_address = var.operator_cidr
    }
    scm_use_main_ip_restriction       = false
    scm_ip_restriction_default_action = "Deny"
    scm_ip_restriction {
      name       = "allow-approved-deployer"
      priority   = 100
      action     = "Allow"
      ip_address = var.operator_cidr
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
  # No zip_deploy_file/publishing credentials/provisioner. The supplied stdlib ZIP
  # is published separately by the approved operator using Azure CLI Entra auth.
}
