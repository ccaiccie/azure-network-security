# Free objects: resource group, two VNets, the private zone with its two links, and two static records.
# Nothing in this file bills by the hour (check current Private DNS zone and query pricing).
# The two VNets are NOT peered on purpose: DNS links and network connectivity are separate things.

locals {
  tags = merge({ lab = "azure-20-private-dns-zones", purpose = "study" }, var.tags)
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- VNets and subnets

resource "azurerm_virtual_network" "app" {
  name                = "${var.name_prefix}-vnet-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.40.0.0/16"]
  # Gate 2 points the whole VNet at the forwarder. An empty list means "use Azure-provided DNS".
  # Check the current provider docs for how an emptied list is applied.
  dns_servers = var.deploy_custom_dns ? ["10.40.3.10"] : []
  tags        = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-vnet-spoke"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.41.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "app_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.40.1.0/24"]
}

resource "azurerm_subnet" "app_pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.40.2.0/24"]
}

resource "azurerm_subnet" "app_dns" {
  name                 = "snet-dns"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.40.3.0/24"]
  # Lab only: the forwarder may need to reach a public resolver in the public_forwarder break/fix.
  # Default outbound access is being retired for new subnets; check current Microsoft docs.
  default_outbound_access_enabled = true
}

resource "azurerm_subnet" "spoke_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.41.1.0/24"]
}

# ---------------------------------------------------------------- the private zone and its links

resource "azurerm_private_dns_zone" "lab" {
  name                = var.zone_name
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# Registration link: VMs in the app VNet get an A record automatically, and resolve the zone.
resource "azurerm_private_dns_zone_virtual_network_link" "app" {
  name                  = "link-app"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.lab.name
  virtual_network_id    = azurerm_virtual_network.app.id
  registration_enabled  = true
  tags                  = local.tags
}

# Resolution link: the spoke VNet can resolve the zone but its VMs are not registered.
# break_fix = no_spoke_link leaves this link out.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  count                 = var.break_fix == "no_spoke_link" ? 0 : 1
  name                  = "link-spoke"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.lab.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags
}

# ---------------------------------------------------------------- static records (free)

# www answers the split-horizon test: the private answer is 10.40.1.10, the public answer (gate 4) is 203.0.113.20.
resource "azurerm_private_dns_a_record" "www" {
  name                = "www"
  zone_name           = azurerm_private_dns_zone.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = 300
  records             = ["10.40.1.10"]
}

# api is the stale-record demo. break_fix = stale_record points it at an address nobody owns, with a long TTL.
resource "azurerm_private_dns_a_record" "api" {
  name                = "api"
  zone_name           = azurerm_private_dns_zone.lab.name
  resource_group_name = azurerm_resource_group.lab.name
  ttl                 = var.break_fix == "stale_record" ? 3600 : 30
  records             = [var.break_fix == "stale_record" ? "10.40.1.99" : "10.40.1.10"]
}
