resource "azurerm_public_ip" "firewall" {
  name                = "firewall-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}
resource "azurerm_firewall_policy" "lab" {
  name                     = "hybrid-policy"
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
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  tags = local.tags
}
resource "azurerm_firewall_policy_rule_collection_group" "private" {
  name               = "hybrid-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  network_rule_collection {
    name     = "deny-healthy-alternate"
    priority = 100
    action   = "Deny"
    rule {
      name                  = "deny-branch-alt-8081"
      protocols             = ["TCP"]
      source_addresses      = ["${local.branch_ip}/32"]
      destination_addresses = ["${local.spoke_ip}/32"]
      destination_ports     = ["8081"]
    }
  }
  network_rule_collection {
    name     = "deny-reverse-new"
    priority = 110
    action   = "Deny"
    rule {
      name                  = "deny-spoke-new-8082"
      protocols             = ["TCP"]
      source_addresses      = ["${local.spoke_ip}/32"]
      destination_addresses = ["${local.branch_ip}/32"]
      destination_ports     = ["8082"]
    }
  }
  network_rule_collection {
    name     = "test-flow"
    priority = 200
    action   = local.test_firewall_action
    rule {
      name                  = "branch-to-spoke-8080"
      protocols             = ["TCP"]
      source_addresses      = ["${local.branch_ip}/32"]
      destination_addresses = ["${local.spoke_ip}/32"]
      destination_ports     = ["8080"]
    }
  }
}
