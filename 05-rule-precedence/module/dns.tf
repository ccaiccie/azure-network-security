resource "azurerm_private_dns_zone" "lab" {
  name                = "policy.test"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  name                 = "hub-resolution"
  private_dns_zone_id  = azurerm_private_dns_zone.lab.id
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
  tags                 = local.tags
}
resource "azurerm_private_dns_a_record" "origin" {
  for_each            = toset(["allowed", "denied"])
  name                = each.key
  private_dns_zone_id = azurerm_private_dns_zone.lab.id
  ttl                 = 30
  records             = [local.backend_ip]
  tags                = local.tags
}
