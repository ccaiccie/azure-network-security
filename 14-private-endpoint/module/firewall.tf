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
  name                     = "pe-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  dns { proxy_enabled = true }
  tags = local.tags
}
resource "azurerm_firewall" "lab" {
  name                = "hub-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  ip_configuration {
    name                 = "data"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  tags = local.tags
}
resource "azurerm_firewall_policy_rule_collection_group" "blob" {
  name               = "blob-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  dynamic "application_rule_collection" {
    for_each = local.clients
    content {
      name     = "${application_rule_collection.key}-blob"
      priority = application_rule_collection.key == "reader" ? 100 : 110
      action   = local.app_actions[application_rule_collection.key]
      rule {
        name              = "${application_rule_collection.key}-to-owned-blob"
        source_addresses  = ["${application_rule_collection.value}/32"]
        destination_fqdns = [local.blob_fqdn]
        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }
  # No terminating network443 Allow, DNAT, URL filtering or TLS decryption.
}
