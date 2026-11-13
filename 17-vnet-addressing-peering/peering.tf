# Peering is two one-way links. Every link has its own four properties.
# The link named X-to-Y lives on X and describes how X treats traffic from Y.

locals {
  # Hub side: transit is offered only when the gate is on. no_transit leaves it off on purpose.
  hub_offers_transit = var.enable_gateway_transit && var.break_fix != "no_transit"
}

# ------------------------------------------------------------------ hub <-> spoke-a
resource "azurerm_virtual_network_peering" "hub_to_a" {
  name                         = "hub-to-spoke-a"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_a.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = local.hub_offers_transit
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_gateway.hub]

  lifecycle {
    precondition {
      condition     = !local.hub_offers_transit || var.create_gateway
      error_message = "Gateway transit needs create_gateway = true: the hub must own a gateway to share."
    }
  }
}

resource "azurerm_virtual_network_peering" "a_to_hub" {
  name                         = "spoke-a-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_a.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.deploy_nva
  allow_gateway_transit        = false
  use_remote_gateways          = var.enable_gateway_transit

  depends_on = [azurerm_virtual_network_gateway.hub, azurerm_virtual_network_peering.hub_to_a]

  lifecycle {
    precondition {
      condition     = !var.enable_gateway_transit || var.create_gateway
      error_message = "enable_gateway_transit needs create_gateway = true: a spoke cannot use a remote gateway that does not exist."
    }
  }
}

# ------------------------------------------------------------------ hub <-> spoke-b
resource "azurerm_virtual_network_peering" "hub_to_b" {
  name                         = "hub-to-spoke-b"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_b.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# break_fix = one_sided leaves this link out: the hub side stays Initiated.
resource "azurerm_virtual_network_peering" "b_to_hub" {
  count                        = var.break_fix == "one_sided" ? 0 : 1
  name                         = "spoke-b-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_b.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.deploy_nva && var.break_fix != "no_forwarded"
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.hub_to_b]
}

# ------------------------------------------------------------------ fix 1: direct spoke-a <-> spoke-b
resource "azurerm_virtual_network_peering" "a_to_b" {
  count                        = var.peer_spokes_directly ? 1 : 0
  name                         = "spoke-a-to-spoke-b"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_a.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_b.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "b_to_a" {
  count                        = var.peer_spokes_directly ? 1 : 0
  name                         = "spoke-b-to-spoke-a"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_b.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_a.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ------------------------------------------------------------------ global peering (hub <-> spoke-c)
resource "azurerm_virtual_network_peering" "hub_to_c" {
  count                        = var.create_global_peering ? 1 : 0
  name                         = "hub-to-spoke-c"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_c[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "c_to_hub" {
  count                        = var.create_global_peering ? 1 : 0
  name                         = "spoke-c-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke_c[0].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
