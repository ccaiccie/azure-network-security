# Gate 2, COSTLY: the Bastion host, its Standard static public IP, a workspace and the BastionAuditLogs diagnostic setting.
# Bastion bills per hour from creation until it is deleted (check current pricing). Needs gate 1 and accept_bastion_cost.
# Attribute names (tunneling_enabled, ip_connect_enabled, shareable_link_enabled, session_recording_enabled) come from
# provider documentation knowledge: check the azurerm docs for your provider version.

resource "azurerm_public_ip" "bastion" {
  count               = local.bastion_on ? 1 : 0
  name                = "${var.name_prefix}-pip-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_bastion_host" "lab" {
  count               = local.bastion_on ? 1 : 0
  name                = "${var.name_prefix}-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = var.bastion_sku
  tags                = local.tags

  # These features need Standard or higher; session recording needs Premium.
  tunneling_enabled         = local.bastion_std ? var.bastion_native_client : false
  ip_connect_enabled        = local.bastion_std ? var.bastion_ip_connect : false
  shareable_link_enabled    = local.bastion_std ? var.bastion_shareable_link : false
  session_recording_enabled = var.bastion_sku == "Premium" ? var.bastion_session_recording : false

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  depends_on = [azurerm_subnet_network_security_group_association.bastion]

  lifecycle {
    precondition {
      condition     = local.bastion_std || !(var.bastion_native_client || var.bastion_ip_connect || var.bastion_shareable_link)
      error_message = "Native client, IP-based connection and shareable links need bastion_sku Standard or Premium."
    }
  }
}

resource "azurerm_log_analytics_workspace" "lab" {
  count               = local.bastion_on ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# Without this setting Bastion sessions leave no log. Check the category name on your own resource.
resource "azurerm_monitor_diagnostic_setting" "bastion" {
  count                      = local.bastion_on ? 1 : 0
  name                       = "diag-bastion"
  target_resource_id         = azurerm_bastion_host.lab[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab[0].id

  enabled_log {
    category = "BastionAuditLogs"
  }
}
