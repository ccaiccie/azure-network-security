# Gate 1 (deploy_hub1) and gate 5 (deploy_hub2): the hubs, their route tables and the VNet connections.
#
# Route table design in hub 1 (labels in brackets):
#   Default   [default]  holds every spoke and the branch. Seen by shared and by connections left on the default.
#   rt-spokes [spokes]   seen by prod and dev: shared, the branch and hub 2. It does NOT hold prod or dev, so prod and dev cannot reach each other.
#   rt-branch [branch]   seen by the branch: prod, shared and hub 2. It does NOT hold dev, so the branch never learns dev.
#   None                 a table that is always empty. Propagating to None means "do not appear anywhere".
#
# Connection settings (association = which table the connection READS; propagation = which tables it WRITES its prefixes into):
#   prod    associated rt-spokes   propagates to default, branch
#   dev     associated rt-spokes   propagates to default
#   shared  associated Default     propagates to default, spokes, branch
#   branch  associated rt-branch   propagates to default, spokes      (vpn.tf)
#   eu2     associated Default(h2) propagates to default, spokes, branch (hub 2)

locals {
  hub1_on = var.deploy_hub1
  hub2_on = var.deploy_hub2

  hub1_id    = try(azurerm_virtual_hub.hub1[0].id, "")
  hub2_id    = try(azurerm_virtual_hub.hub2[0].id, "")
  h1_default = "${local.hub1_id}/hubRouteTables/defaultRouteTable"
  h1_none    = "${local.hub1_id}/hubRouteTables/noneRouteTable"
  h2_default = "${local.hub2_id}/hubRouteTables/defaultRouteTable"
  h2_none    = "${local.hub2_id}/hubRouteTables/noneRouteTable"
  rt_spokes  = try(azurerm_virtual_hub_route_table.spokes1[0].id, "")
  rt_branch  = try(azurerm_virtual_hub_route_table.branch1[0].id, "")

  # Faults (Activity 8). A label typo is silently accepted: the prefix simply lands in no table.
  prod_labels    = var.fault == "label_typo" ? ["default", "brnach"] : ["default", "branch"]
  shared_to_none = var.fault == "shared_none"
}

resource "azurerm_virtual_hub" "hub1" {
  count                  = local.hub1_on ? 1 : 0
  name                   = "${var.name_prefix}-hub1"
  resource_group_name    = azurerm_resource_group.lab.name
  location               = var.location
  virtual_wan_id         = azurerm_virtual_wan.wan.id
  sku                    = "Standard"
  address_prefix         = "10.100.0.0/24"
  hub_routing_preference = var.hub_routing_preference
  tags                   = local.tags
}

resource "azurerm_virtual_hub_route_table" "spokes1" {
  count          = local.hub1_on ? 1 : 0
  name           = "rt-spokes"
  virtual_hub_id = azurerm_virtual_hub.hub1[0].id
  labels         = ["spokes"]

  # A static route in a table points at a connection (for example an NVA or firewall). Check current docs for the accepted next-hop types.
  dynamic "route" {
    for_each = var.static_routes ? [1] : []
    content {
      name              = "to-shared-services"
      destinations_type = "CIDR"
      destinations      = ["10.251.0.0/24"]
      next_hop_type     = "ResourceId"
      next_hop          = azurerm_virtual_hub_connection.shared[0].id
    }
  }
}

resource "azurerm_virtual_hub_route_table" "branch1" {
  count          = local.hub1_on ? 1 : 0
  name           = "rt-branch"
  virtual_hub_id = azurerm_virtual_hub.hub1[0].id
  labels         = ["branch"]
}

resource "azurerm_virtual_hub_connection" "prod" {
  count                     = local.hub1_on ? 1 : 0
  name                      = "conn-prod"
  virtual_hub_id            = azurerm_virtual_hub.hub1[0].id
  remote_virtual_network_id = azurerm_virtual_network.spoke["prod"].id
  internet_security_enabled = false

  routing {
    associated_route_table_id = local.rt_spokes
    propagated_route_table {
      route_table_ids = [local.h1_default]
      labels          = local.prod_labels
    }
  }
}

resource "azurerm_virtual_hub_connection" "dev" {
  count                     = local.hub1_on ? 1 : 0
  name                      = "conn-dev"
  virtual_hub_id            = azurerm_virtual_hub.hub1[0].id
  remote_virtual_network_id = azurerm_virtual_network.spoke["dev"].id
  internet_security_enabled = false

  routing {
    associated_route_table_id = local.rt_spokes
    propagated_route_table {
      route_table_ids = [local.h1_default]
      labels          = ["default"]
    }
  }
}

resource "azurerm_virtual_hub_connection" "shared" {
  count                     = local.hub1_on ? 1 : 0
  name                      = "conn-shared"
  virtual_hub_id            = azurerm_virtual_hub.hub1[0].id
  remote_virtual_network_id = azurerm_virtual_network.spoke["shared"].id
  internet_security_enabled = false

  routing {
    associated_route_table_id = local.h1_default
    propagated_route_table {
      route_table_ids = local.shared_to_none ? [local.h1_none] : [local.h1_default]
      labels          = local.shared_to_none ? [] : ["default", "spokes", "branch"]
    }

    # A static route on the VNet connection: a prefix behind an NVA in the spoke. Check current docs for the propagate-static-routes behaviour.
    dynamic "static_vnet_route" {
      for_each = var.static_routes ? [1] : []
      content {
        name                = "to-nva-prefix"
        address_prefixes    = ["10.250.0.0/24"]
        next_hop_ip_address = "10.103.0.10"
      }
    }
  }
}

# ---------------------------------------------------------------- hub 2

resource "azurerm_virtual_hub" "hub2" {
  count               = local.hub2_on ? 1 : 0
  name                = "${var.name_prefix}-hub2"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location2
  virtual_wan_id      = azurerm_virtual_wan.wan.id
  sku                 = "Standard"
  address_prefix      = "10.200.0.0/24"
  tags                = local.tags
}

# The labels only travel to a table that carries the same label, so hub 2 needs tables that carry "spokes" and "branch" too.
resource "azurerm_virtual_hub_route_table" "spokes2" {
  count          = local.hub2_on ? 1 : 0
  name           = "rt-spokes"
  virtual_hub_id = azurerm_virtual_hub.hub2[0].id
  labels         = ["spokes"]
}

resource "azurerm_virtual_hub_route_table" "branch2" {
  count          = local.hub2_on ? 1 : 0
  name           = "rt-branch"
  virtual_hub_id = azurerm_virtual_hub.hub2[0].id
  labels         = ["branch"]
}

resource "azurerm_virtual_hub_connection" "eu2" {
  count                     = local.hub2_on ? 1 : 0
  name                      = "conn-eu2"
  virtual_hub_id            = azurerm_virtual_hub.hub2[0].id
  remote_virtual_network_id = azurerm_virtual_network.spoke["eu2"].id
  internet_security_enabled = false

  routing {
    associated_route_table_id = local.h2_default
    propagated_route_table {
      route_table_ids = [local.h2_default]
      labels          = ["default", "spokes", "branch"]
    }
  }
}
