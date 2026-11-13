resource "azurerm_public_ip" "firewall_management" {
  name                = "firewall-management-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
resource "azurerm_firewall_policy" "lab" {
  name                     = "forced-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  private_ip_ranges        = var.source_mode == "preserve" ? ["0.0.0.0/0"] : ["IANAPrivateRanges"]
  tags                     = local.tags
  # No parent, application rule, DNAT, TLS inspection or auto-learn behavior.
}
resource "azurerm_firewall" "lab" {
  name                = "hub-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  ip_configuration {
    name      = "data"
    subnet_id = azurerm_subnet.firewall.id
    # Intentionally no tenant data public IP.
  }
  management_ip_configuration {
    name                 = "management"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_management.id
  }
  tags = local.tags
}
resource "azurerm_firewall_policy_rule_collection_group" "forced" {
  name               = "forced-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  network_rule_collection {
    name     = "deny-azure-negative"
    priority = 100
    action   = "Deny"
    rule {
      name                  = "deny-app-8081"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = [azurerm_public_ip.endpoint["origin"].ip_address]
      destination_ports     = ["8081"]
    }
  }
  network_rule_collection {
    name     = "test-flow"
    priority = 200
    action   = local.test_firewall_action
    rule {
      name                  = "app-to-controlled-origin"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = [azurerm_public_ip.endpoint["origin"].ip_address]
      destination_ports     = ["8080", "8082"]
    }
  }
}
