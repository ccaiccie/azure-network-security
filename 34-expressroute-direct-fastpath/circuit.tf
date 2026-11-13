# Gates 2 and 4: circuits. Neither can work without a provider or physical fibre.
# Read the plan; apply only if you own the contract or the port.

resource "azurerm_express_route_circuit" "partner" {
  count                 = var.deploy_circuit && !var.deploy_direct_port ? 1 : 0
  name                  = "${var.name_prefix}-circuit"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  service_provider_name = var.service_provider_name
  peering_location      = var.peering_location
  bandwidth_in_mbps     = var.circuit_bandwidth_mbps
  tags                  = local.tags

  sku {
    tier   = var.circuit_tier
    family = var.circuit_family
  }
}

resource "azurerm_express_route_port" "direct" {
  count               = var.deploy_direct_port ? 1 : 0
  name                = "${var.name_prefix}-port"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  peering_location    = var.direct_peering_location
  bandwidth_in_gbps   = var.direct_bandwidth_gbps
  encapsulation       = "Dot1Q"
  tags                = local.tags
}

resource "azurerm_express_route_circuit" "on_direct" {
  count                 = var.deploy_direct_port ? 1 : 0
  name                  = "${var.name_prefix}-direct-circuit"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  express_route_port_id = azurerm_express_route_port.direct[0].id
  bandwidth_in_gbps     = var.direct_circuit_gbps
  tags                  = local.tags

  sku {
    tier   = var.circuit_tier
    family = var.circuit_family
  }
}

locals {
  circuit_id = (
    var.existing_circuit_id != "" ? var.existing_circuit_id :
    var.deploy_direct_port ? try(azurerm_express_route_circuit.on_direct[0].id, "") :
    try(azurerm_express_route_circuit.partner[0].id, "")
  )
}
