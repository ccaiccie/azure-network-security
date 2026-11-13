# Gate 4 (create_public_zone): a public Azure DNS zone with the SAME name as the private zone.
# This is split-horizon DNS: VMs in a linked VNet get the private answer, everyone else the public one.
# The zone is not delegated from any registrar, so no real resolver on the Internet asks it.
# You test it by asking one of its name servers directly (see the output public_zone_name_servers).
# Check current Azure DNS pricing: a zone is billed per month plus per million queries.

resource "azurerm_dns_zone" "public" {
  count               = var.create_public_zone ? 1 : 0
  name                = var.zone_name
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# Same name as the private record, different answer (203.0.113.20 is an RFC 5737 documentation address).
resource "azurerm_dns_a_record" "www" {
  count               = var.create_public_zone ? 1 : 0
  name                = "www"
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 300
  records             = ["203.0.113.20"]
}

# Exists only in the public zone. A VM in a linked VNet asking for it gets NXDOMAIN from the private zone.
resource "azurerm_dns_a_record" "only_public" {
  count               = var.create_public_zone ? 1 : 0
  name                = "only-public"
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 300
  records             = ["203.0.113.30"]
}
