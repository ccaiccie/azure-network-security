resource "azurerm_firewall_policy" "lab" {
  name                     = "private-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags
  # No parent, application, DNAT, TLS, custom SNAT ranges or external allow rules.
}
resource "azurerm_firewall" "lab" {
  name                = "hub-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_Hub"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.lab.id
    public_ip_count = 1
  }
  tags = local.tags
}
resource "azurerm_firewall_policy_rule_collection_group" "private" {
  name               = "private-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  network_rule_collection {
    name     = "deny-healthy-alternate"
    priority = 100
    action   = "Deny"
    rule {
      name                  = "deny-app-alt-8081"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = ["${local.backend_ip}/32"]
      destination_ports     = ["8081"]
    }
  }
  network_rule_collection {
    name     = "deny-reverse-new"
    priority = 110
    action   = "Deny"
    rule {
      name                  = "deny-backend-new-8082"
      protocols             = ["TCP"]
      source_addresses      = ["${local.backend_ip}/32"]
      destination_addresses = ["${local.app_ip}/32"]
      destination_ports     = ["8082"]
    }
  }
  network_rule_collection {
    name     = "test-flow"
    priority = 200
    action   = local.test_firewall_action
    rule {
      name                  = "app-to-backend-8080"
      protocols             = ["TCP"]
      source_addresses      = ["${local.app_ip}/32"]
      destination_addresses = ["${local.backend_ip}/32"]
      destination_ports     = ["8080"]
    }
  }
}
