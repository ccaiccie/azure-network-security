# Every resource in this lab is behind a gate that defaults to false.
# With all gates closed, terraform plan creates nothing.

locals {
  tags = {
    scenario = "expressroute-multiregion"
    purpose  = "study-lab"
  }

  regions = {
    a = {
      location   = var.location_a
      hub_cidr   = "10.1.0.0/16"
      gw_cidr    = "10.1.255.0/27"
      spoke_cidr = "10.11.0.0/16"
      wl_cidr    = "10.11.1.0/24"
      vm_ip      = "10.11.1.10"
    }
    b = {
      location   = var.location_b
      hub_cidr   = "10.2.0.0/16"
      gw_cidr    = "10.2.255.0/27"
      spoke_cidr = "10.12.0.0/16"
      wl_cidr    = "10.12.1.0/24"
      vm_ip      = "10.12.1.10"
    }
  }

  lab      = var.deploy_lab ? local.regions : {}
  gateways = var.deploy_lab && var.deploy_er_gateways ? local.regions : {}
  vms      = var.deploy_lab && var.deploy_test_vms ? local.regions : {}
  circuits = var.deploy_lab && var.create_circuits ? var.circuits : {}

  # Circuits owned here, plus any you passed in by ID.
  circuit_ids = merge(
    var.existing_circuit_ids,
    { for k, c in azurerm_express_route_circuit.this : k => c.id }
  )

  # Four connections: every hub to every circuit (keys a-a, a-b, b-a, b-b).
  connections = var.deploy_lab && var.deploy_er_gateways && var.create_connections ? {
    for p in setproduct(keys(local.regions), keys(var.circuits)) :
    "${p[0]}-${p[1]}" => { hub = p[0], circuit = p[1] }
  } : {}
}

resource "azurerm_resource_group" "lab" {
  count = var.deploy_lab ? 1 : 0

  name     = "${var.name_prefix}-lab"
  location = var.location_a
  tags     = local.tags
}
