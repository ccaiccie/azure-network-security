# Gate 3 (deploy_s2s): the local network gateway (what Azure knows about the on-premises device)
# and the connection (the IPsec tunnel itself). Needs gates 1 and 2.

locals {
  s2s_on        = var.deploy_vpn_gateway && var.deploy_onprem_sim && var.deploy_s2s
  plain_bgp_ip  = "10.70.255.1"
  bgp_peer_ip   = var.use_apipa ? var.onprem_bgp_ip : local.plain_bgp_ip
  lng_all_prefs = concat(var.lng_prefixes, var.enable_bgp && !var.use_apipa ? ["${local.plain_bgp_ip}/32"] : [])
}

resource "azurerm_local_network_gateway" "onprem" {
  count               = local.s2s_on ? 1 : 0
  name                = "${var.name_prefix}-lng-onprem"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  gateway_address     = azurerm_public_ip.edge[0].ip_address
  address_space       = local.lng_all_prefs
  tags                = local.tags

  dynamic "bgp_settings" {
    for_each = var.enable_bgp ? [1] : []
    content {
      asn                 = var.onprem_bgp_asn
      bgp_peering_address = local.bgp_peer_ip
    }
  }
}

resource "azurerm_virtual_network_gateway_connection" "s2s" {
  count                      = local.s2s_on ? 1 : 0
  name                       = "${var.name_prefix}-conn-onprem"
  location                   = azurerm_resource_group.lab.location
  resource_group_name        = azurerm_resource_group.lab.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem[0].id
  shared_key                 = var.shared_key
  connection_protocol        = "IKEv2"
  enable_bgp                 = var.enable_bgp
  dpd_timeout_seconds        = var.dpd_timeout_seconds
  tags                       = local.tags

  dynamic "ipsec_policy" {
    for_each = var.custom_ipsec_policy ? [1] : []
    content {
      ike_encryption   = "AES256"
      ike_integrity    = "SHA256"
      dh_group         = "DHGroup14"
      ipsec_encryption = "AES256"
      ipsec_integrity  = "SHA256"
      pfs_group        = "PFS14"
      sa_lifetime      = 27000
      sa_datasize      = 102400000
    }
  }

  lifecycle {
    precondition {
      condition     = var.shared_key != ""
      error_message = "Set shared_key (16 or more characters) when deploy_s2s is true."
    }
  }
}
