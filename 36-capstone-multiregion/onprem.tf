# REFERENCE SKELETON: optional on-premises simulation (gate 8) and a simulated VPN tunnel (gate 9, billable).
# ExpressRoute cannot be simulated with Terraform alone (it needs a provider and a circuit), so the
# simulation uses a VNet-to-VNet VPN with BGP to stand in for "on-premises". The ExpressRoute parts of the
# design are paper-only in this skeleton.

resource "azurerm_resource_group" "onprem" {
  count    = var.deploy_onprem_sim ? 1 : 0
  name     = "${var.name_prefix}-onprem-rg"
  location = var.location_a
  tags     = local.tags
}

resource "azurerm_virtual_network" "onprem" {
  count               = var.deploy_onprem_sim ? 1 : 0
  name                = "${var.name_prefix}-onprem"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.onprem[0].name
  address_space       = ["10.200.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "onprem_dns" {
  count                = var.deploy_onprem_sim ? 1 : 0
  name                 = "snet-dns"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = ["10.200.10.0/24"]
}

resource "azurerm_subnet" "onprem_app" {
  count                = var.deploy_onprem_sim ? 1 : 0
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = ["10.200.20.0/24"]
}

resource "azurerm_subnet" "onprem_gw" {
  count                = var.deploy_onprem_sim && var.deploy_vpn_sim ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = ["10.200.255.0/27"]
}

resource "azurerm_public_ip" "gw_a" {
  count               = var.deploy_vpn_sim && var.deploy_region_a ? 1 : 0
  name                = "${var.name_prefix}-pip-vpn-a"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.region["a"].name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_public_ip" "gw_onprem" {
  count               = var.deploy_vpn_sim && var.deploy_onprem_sim ? 1 : 0
  name                = "${var.name_prefix}-pip-vpn-onprem"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.onprem[0].name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

# VPN gateway in hub A. A zone-redundant SKU (VpnGw1AZ) needs a zone-redundant Standard public IP; check current docs for SKU availability and size.
resource "azurerm_virtual_network_gateway" "hub_a" {
  count               = var.deploy_vpn_sim && var.deploy_region_a ? 1 : 0
  name                = "${var.name_prefix}-vpngw-a"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.region["a"].name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  enable_bgp          = true
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig"
    public_ip_address_id = azurerm_public_ip.gw_a[0].id
    subnet_id            = azurerm_subnet.hub["a/GatewaySubnet"].id
  }

  bgp_settings {
    asn = 65515
  }

  lifecycle {
    precondition {
      condition     = var.deploy_onprem_sim && length(var.vpn_shared_key) >= 16
      error_message = "Gate 9 needs gate 8 and a vpn_shared_key of at least 16 characters."
    }
  }
}

resource "azurerm_virtual_network_gateway" "onprem" {
  count               = var.deploy_vpn_sim && var.deploy_onprem_sim ? 1 : 0
  name                = "${var.name_prefix}-vpngw-onprem"
  location            = var.location_a
  resource_group_name = azurerm_resource_group.onprem[0].name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  enable_bgp          = true
  tags                = local.tags

  ip_configuration {
    name                 = "ipconfig"
    public_ip_address_id = azurerm_public_ip.gw_onprem[0].id
    subnet_id            = azurerm_subnet.onprem_gw[0].id
  }

  bgp_settings {
    asn = 65010
  }
}

resource "azurerm_virtual_network_gateway_connection" "a_to_onprem" {
  count                           = var.deploy_vpn_sim && var.deploy_onprem_sim && var.deploy_region_a ? 1 : 0
  name                            = "${var.name_prefix}-conn-a-to-onprem"
  location                        = var.location_a
  resource_group_name             = azurerm_resource_group.region["a"].name
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.hub_a[0].id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.onprem[0].id
  shared_key                      = var.vpn_shared_key
  enable_bgp                      = true
  tags                            = local.tags
}

resource "azurerm_virtual_network_gateway_connection" "onprem_to_a" {
  count                           = var.deploy_vpn_sim && var.deploy_onprem_sim && var.deploy_region_a ? 1 : 0
  name                            = "${var.name_prefix}-conn-onprem-to-a"
  location                        = var.location_a
  resource_group_name             = azurerm_resource_group.onprem[0].name
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.onprem[0].id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.hub_a[0].id
  shared_key                      = var.vpn_shared_key
  enable_bgp                      = true
  tags                            = local.tags
}
