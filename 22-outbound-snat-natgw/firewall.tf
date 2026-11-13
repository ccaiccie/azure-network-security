# Gate 4 (deploy_firewall): Azure Firewall Standard in its own subnet, a policy that allows web traffic
# from snet-fw, and a route table that sends 0.0.0.0/0 from snet-fw to the firewall.
# This is the most expensive gate: destroy it as soon as Activity 6 is done.

resource "azurerm_subnet" "firewall" {
  count                = var.deploy_firewall ? 1 : 0
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.50.250.0/26"]
}

resource "azurerm_public_ip" "fw" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-fw-pip"
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
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "lab" {
  count              = var.deploy_firewall ? 1 : 0
  name               = "rcg-egress"
  firewall_policy_id = azurerm_firewall_policy.lab[0].id
  priority           = 200

  network_rule_collection {
    name     = "allow-web-out"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "snet-fw-web"
      protocols             = ["TCP"]
      source_addresses      = ["10.50.3.0/24"]
      destination_addresses = ["*"]
      destination_ports     = ["80", "443"]
    }
  }
}

resource "azurerm_firewall" "lab" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab[0].id
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.firewall[0].id
    public_ip_address_id = azurerm_public_ip.fw[0].id
  }
}

resource "azurerm_route_table" "fw" {
  count               = var.deploy_firewall ? 1 : 0
  name                = "${var.name_prefix}-rt-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.lab[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "fw" {
  count          = var.deploy_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.fw.id
  route_table_id = azurerm_route_table.fw[0].id
}
