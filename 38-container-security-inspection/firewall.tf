# Gates 1, 3 and 4. The firewall bills by the hour; the policy and routes are free objects but need the firewall.

resource "azurerm_public_ip" "fw" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-fw-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# The Basic tier needs a management public IP and the management subnet.
resource "azurerm_public_ip" "fw_mgmt" {
  count               = var.deploy_firewall && var.firewall_sku == "Basic" ? 1 : 0
  name                = "${var.name_prefix}-fw-mgmt-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "lab" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-fwpolicy"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = var.firewall_sku
  tags                = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  count              = var.deploy_firewall ? 1 : 0
  name               = "aks"
  firewall_policy_id = azurerm_firewall_policy.lab[0].id
  priority           = 200

  # Application rules match by domain name. The FQDN tag covers the platform domains AKS needs;
  # its members change, so check current docs for add-on domains.
  application_rule_collection {
    name     = "app-aks"
    priority = 200
    action   = "Allow"

    dynamic "rule" {
      for_each = var.include_fqdn_tag_rule ? [1] : []
      content {
        name = "aks-fqdn-tag"
        protocols {
          type = "Http"
          port = 80
        }
        protocols {
          type = "Https"
          port = 443
        }
        source_addresses      = [azurerm_subnet.nodes.address_prefixes[0]]
        destination_fqdn_tags = ["AzureKubernetesService"]
      }
    }

    # Test rule for Activity 4. egress_rule_source decides which source the firewall must see.
    rule {
      name = "allow-test-fqdn"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [var.egress_rule_source]
      destination_fqdns = [var.egress_test_fqdn]
    }
  }

  dynamic "network_rule_collection" {
    for_each = var.add_legacy_network_rules ? [1] : []
    content {
      name     = "net-aks-legacy"
      priority = 100
      action   = "Allow"
      rule {
        name                  = "tunnel-udp-1194"
        protocols             = ["UDP"]
        source_addresses      = [azurerm_subnet.nodes.address_prefixes[0]]
        destination_addresses = ["AzureCloud.${var.location}"]
        destination_ports     = ["1194"]
      }
      rule {
        name                  = "tunnel-tcp-9000"
        protocols             = ["TCP"]
        source_addresses      = [azurerm_subnet.nodes.address_prefixes[0]]
        destination_addresses = ["AzureCloud.${var.location}"]
        destination_ports     = ["9000"]
      }
    }
  }

  # Gate 3: publish tcp/80 on the firewall public IP to the internal load balancer.
  dynamic "nat_rule_collection" {
    for_each = var.enable_dnat ? [1] : []
    content {
      name     = "dnat-ingress"
      priority = 100
      action   = "Dnat"
      rule {
        name                = "http-to-ilb"
        protocols           = ["TCP"]
        source_addresses    = ["*"]
        destination_address = azurerm_public_ip.fw[0].ip_address
        destination_ports   = ["80"]
        translated_address  = var.ingress_ilb_ip
        translated_port     = 80
      }
    }
  }
}

resource "azurerm_firewall" "lab" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku
  firewall_policy_id  = azurerm_firewall_policy.lab[0].id
  tags                = local.tags

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.fw[0].id
  }

  dynamic "management_ip_configuration" {
    for_each = var.firewall_sku == "Basic" ? [1] : []
    content {
      name                 = "fw-mgmt-ipconfig"
      subnet_id            = azurerm_subnet.firewall_mgmt.id
      public_ip_address_id = azurerm_public_ip.fw_mgmt[0].id
    }
  }
}

# ---------------------------------------------------------------- routes that need the firewall addresses
# The next hop is read from the firewall resource. Never type the private IP as a permanent value.
resource "azurerm_route" "default_to_firewall" {
  count                  = var.deploy_firewall ? 1 : 0
  name                   = "default-to-firewall"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.nodes.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.lab[0].ip_configuration[0].private_ip_address
}

# Replies to the firewall's own public IP must not be pulled back into the firewall.
resource "azurerm_route" "firewall_pip_direct" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "firewall-pip-direct"
  resource_group_name = azurerm_resource_group.lab.name
  route_table_name    = azurerm_route_table.nodes.name
  address_prefix      = "${azurerm_public_ip.fw[0].ip_address}/32"
  next_hop_type       = "Internet"
}

# Activity 6: replies to your own public IP leave directly (trades inspection for a working public Service).
resource "azurerm_route" "client_bypass" {
  count               = var.deploy_firewall && var.bypass_client_cidr != "" ? 1 : 0
  name                = "client-bypass"
  resource_group_name = azurerm_resource_group.lab.name
  route_table_name    = azurerm_route_table.nodes.name
  address_prefix      = var.bypass_client_cidr
  next_hop_type       = "Internet"
}

# ---------------------------------------------------------------- gate 4: logs
resource "azurerm_log_analytics_workspace" "lab" {
  count               = var.deploy_firewall && var.enable_diagnostics ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# Resource-specific tables (AZFWApplicationRule, AZFWNetworkRule, AZFWNatRule). Check current category names.
resource "azurerm_monitor_diagnostic_setting" "fw" {
  count                          = var.deploy_firewall && var.enable_diagnostics ? 1 : 0
  name                           = "${var.name_prefix}-fw-diag"
  target_resource_id             = azurerm_firewall.lab[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab[0].id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWNatRule"
  }
}
