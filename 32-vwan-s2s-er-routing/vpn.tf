# Gate 4 (deploy_vpn): the hub 1 VPN gateway, the VPN site that describes vm-edge, and the connection.
# The connection is where routing is decided for the branch:
#   association  rt-branch  (what the branch is told: prod, shared, hub 2; not dev)
#   propagation  default and spokes (where the branch prefixes appear)
# Gate 6 (deploy_er_gateway): an ExpressRoute gateway in hub 1. It bills even with no circuit, and the lab creates no circuit.

resource "azurerm_vpn_gateway" "hub1" {
  count               = local.vpn_on ? 1 : 0
  name                = "${var.name_prefix}-hub1-vpngw"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  virtual_hub_id      = azurerm_virtual_hub.hub1[0].id
  scale_unit          = var.vpn_scale_unit
  tags                = local.tags

  lifecycle {
    precondition {
      condition     = length(var.shared_key) >= 16
      error_message = "shared_key must be 16 or more characters."
    }
  }
}

resource "azurerm_vpn_site" "branch" {
  count               = local.vpn_on ? 1 : 0
  name                = "site-branch"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  virtual_wan_id      = azurerm_virtual_wan.wan.id
  address_cidrs       = ["10.80.0.0/24", "10.80.2.0/24"]
  tags                = local.tags

  link {
    name          = "edge"
    ip_address    = azurerm_public_ip.edge[0].ip_address
    provider_name = "lab"
    speed_in_mbps = 50

    bgp {
      asn             = 65020
      peering_address = "10.80.0.10"
    }
  }
}

resource "azurerm_vpn_gateway_connection" "branch" {
  count              = local.vpn_on ? 1 : 0
  name               = "conn-branch"
  vpn_gateway_id     = azurerm_vpn_gateway.hub1[0].id
  remote_vpn_site_id = azurerm_vpn_site.branch[0].id

  routing {
    associated_route_table = var.fault == "branch_assoc_default" ? local.h1_default : local.rt_branch
    propagated_route_table {
      route_table_ids = [local.h1_default]
      labels          = ["default", "spokes"]
    }
  }

  vpn_link {
    name             = "link-edge"
    vpn_site_link_id = azurerm_vpn_site.branch[0].link[0].id
    shared_key       = var.shared_key
    bgp_enabled      = true
    protocol         = "IKEv2"
  }
}

resource "azurerm_express_route_gateway" "hub1" {
  count               = var.deploy_er_gateway && var.deploy_hub1 ? 1 : 0
  name                = "${var.name_prefix}-hub1-ergw"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  virtual_hub_id      = azurerm_virtual_hub.hub1[0].id
  scale_units         = var.er_scale_units
  tags                = local.tags
}

# Only created when you bring your own circuit: pass the resource ID of its private peering.
resource "azurerm_express_route_connection" "branch" {
  count                            = var.deploy_er_gateway && var.deploy_hub1 && var.er_circuit_peering_id != "" ? 1 : 0
  name                             = "conn-er-branch"
  express_route_gateway_id         = azurerm_express_route_gateway.hub1[0].id
  express_route_circuit_peering_id = var.er_circuit_peering_id

  routing {
    associated_route_table_id = local.rt_branch
    propagated_route_table {
      route_table_ids = [local.h1_default]
      labels          = ["default", "spokes"]
    }
  }
}
