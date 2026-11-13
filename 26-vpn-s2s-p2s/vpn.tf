# Gate 1 (deploy_vpn_gateway): the Azure VPN gateway. Gate 4 (deploy_p2s) adds the point-to-site block to it.
# Creation takes a long time (often 30 to 45 minutes). Changing SKU or active-active later can be slow or force a rebuild.

locals {
  gw_count     = var.deploy_vpn_gateway ? (var.active_active ? 2 : 1) : 0
  azure_apipa  = ["169.254.21.1", "169.254.22.1"]
  p2s_entra    = var.p2s_auth_type == "entra"
  p2s_protocol = local.p2s_entra ? ["OpenVPN"] : var.p2s_protocols
}

resource "azurerm_public_ip" "gw" {
  count               = local.gw_count
  name                = "${var.name_prefix}-gw-pip${count.index + 1}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.deploy_vpn_gateway ? 1 : 0
  name                = "${var.name_prefix}-vpngw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_sku
  generation          = var.vpn_generation
  active_active       = var.active_active
  enable_bgp          = var.enable_bgp
  tags                = local.tags

  dynamic "ip_configuration" {
    for_each = azurerm_public_ip.gw
    content {
      name                          = "gwip${ip_configuration.key + 1}"
      public_ip_address_id          = ip_configuration.value.id
      private_ip_address_allocation = "Dynamic"
      subnet_id                     = azurerm_subnet.gateway.id
    }
  }

  dynamic "bgp_settings" {
    for_each = var.enable_bgp ? [1] : []
    content {
      asn = var.azure_bgp_asn

      dynamic "peering_addresses" {
        for_each = var.use_apipa ? range(local.gw_count) : []
        content {
          ip_configuration_name = "gwip${peering_addresses.value + 1}"
          apipa_addresses       = [local.azure_apipa[peering_addresses.value]]
        }
      }
    }
  }

  dynamic "vpn_client_configuration" {
    for_each = var.deploy_p2s ? [1] : []
    content {
      address_space        = [var.p2s_address_pool]
      vpn_client_protocols = local.p2s_protocol
      vpn_auth_types       = local.p2s_entra ? ["AAD"] : ["Certificate"]
      aad_tenant           = local.p2s_entra ? "https://login.microsoftonline.com/${var.entra_tenant_id}/" : null
      aad_audience         = local.p2s_entra ? var.entra_audience : null
      aad_issuer           = local.p2s_entra ? "https://sts.windows.net/${var.entra_tenant_id}/" : null

      dynamic "root_certificate" {
        for_each = local.p2s_entra ? [] : [1]
        content {
          name             = "lab-root"
          public_cert_data = var.p2s_root_cert_public_data
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.use_apipa || var.enable_bgp
      error_message = "use_apipa needs enable_bgp = true."
    }
    precondition {
      condition     = !var.deploy_p2s || local.p2s_entra || var.p2s_root_cert_public_data != ""
      error_message = "Certificate authentication needs p2s_root_cert_public_data."
    }
    precondition {
      condition     = !var.deploy_p2s || !local.p2s_entra || (var.entra_tenant_id != "" && var.entra_audience != "")
      error_message = "Entra ID authentication needs entra_tenant_id and entra_audience."
    }
  }
}
