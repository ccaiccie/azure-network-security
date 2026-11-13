# Gate 5 (deploy_firewall): a hub VNet with Azure Firewall Standard (10.82.0.4), a policy that allows the app port from the
# client VNet to the server VNet, structured logs to the workspace, and user-defined routes.
# EXPENSIVE: the firewall bills by the hour. It also needs a public IP (the only one in the lab).
# symmetric_return = false leaves the server subnet without a route table: replies bypass the firewall (break/fix 2).

locals {
  fw_on = var.deploy_firewall && var.deploy_monitoring
}

resource "azurerm_virtual_network" "hub" {
  count               = local.fw_on ? 1 : 0
  name                = "${var.name_prefix}-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.82.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "fw" {
  count                = local.fw_on ? 1 : 0
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefixes     = ["10.82.0.0/26"]
}

resource "azurerm_virtual_network_peering" "client_to_hub" {
  count                     = local.fw_on ? 1 : 0
  name                      = "client-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.client.name
  remote_virtual_network_id = azurerm_virtual_network.hub[0].id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_client" {
  count                     = local.fw_on ? 1 : 0
  name                      = "hub-to-client"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub[0].name
  remote_virtual_network_id = azurerm_virtual_network.client.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "server_to_hub" {
  count                     = local.fw_on ? 1 : 0
  name                      = "server-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.server.name
  remote_virtual_network_id = azurerm_virtual_network.hub[0].id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_server" {
  count                     = local.fw_on ? 1 : 0
  name                      = "hub-to-server"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub[0].name
  remote_virtual_network_id = azurerm_virtual_network.server.id
  allow_forwarded_traffic   = true
}

resource "azurerm_public_ip" "fw" {
  count               = local.fw_on ? 1 : 0
  name                = "${var.name_prefix}-fw-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "lab" {
  count               = local.fw_on ? 1 : 0
  name                = "${var.name_prefix}-fw-policy"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "lab" {
  count              = local.fw_on ? 1 : 0
  name               = "rcg-lab"
  firewall_policy_id = azurerm_firewall_policy.lab[0].id
  priority           = 200

  network_rule_collection {
    name     = "nrc-app"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-app-port"
      protocols             = ["TCP"]
      source_addresses      = ["10.80.0.0/24"]
      destination_addresses = ["10.81.0.0/24"]
      destination_ports     = [tostring(var.app_port)]
    }
  }
}

resource "azurerm_firewall" "lab" {
  count               = local.fw_on ? 1 : 0
  name                = "${var.name_prefix}-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab[0].id
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.fw[0].id
    public_ip_address_id = azurerm_public_ip.fw[0].id
  }
}

# Structured (resource-specific) logs: the Dedicated destination type is what creates the AZFW tables.
resource "azurerm_monitor_diagnostic_setting" "fw" {
  count                          = local.fw_on ? 1 : 0
  name                           = "fw-to-law"
  target_resource_id             = azurerm_firewall.lab[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab[0].id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWFlowTrace"
  }
}

# Client subnet: traffic for the server VNet goes to the firewall (a UDR beats the peering system route).
resource "azurerm_route_table" "client" {
  count               = local.fw_on ? 1 : 0
  name                = "${var.name_prefix}-rt-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "to-server-via-fw"
    address_prefix         = "10.81.0.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "client" {
  count          = local.fw_on ? 1 : 0
  subnet_id      = azurerm_subnet.client.id
  route_table_id = azurerm_route_table.client[0].id
}

# Server subnet: only with symmetric_return = true do the replies go back through the firewall.
resource "azurerm_route_table" "server" {
  count               = local.fw_on && var.symmetric_return ? 1 : 0
  name                = "${var.name_prefix}-rt-server"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "to-client-via-fw"
    address_prefix         = "10.80.0.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "server" {
  count          = local.fw_on && var.symmetric_return ? 1 : 0
  subnet_id      = azurerm_subnet.server.id
  route_table_id = azurerm_route_table.server[0].id
}
