resource "azurerm_cdn_frontdoor_firewall_policy" "edge" {
  name                              = "wafedgepolicy"
  resource_group_name               = azurerm_resource_group.lab.name
  sku_name                          = "Premium_AzureFrontDoor"
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403
  custom_rule {
    name     = "BlockOtherSockets"
    priority = 10
    enabled  = true
    type     = "MatchRule"
    action   = "Block"
    match_condition {
      match_variable     = "SocketAddr"
      operator           = "IPMatch"
      negation_condition = true
      match_values       = [var.operator_cidr]
    }
  }
  custom_rule {
    name     = "BlockEdgeMarker"
    priority = 20
    enabled  = true
    type     = "MatchRule"
    action   = "Block"
    match_condition {
      match_variable = "RequestHeader"
      selector       = "X-Lab-Edge-Block"
      operator       = "Equal"
      match_values   = ["1"]
    }
  }
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
  tags = local.tags
}
resource "azurerm_web_application_firewall_policy" "gateway" {
  name                = "gateway-waf-policy"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 1
  }
  custom_rules {
    name      = "BlockMissingFDID"
    priority  = 10
    rule_type = "MatchRule"
    action    = "Block"
    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "X-Azure-FDID"
      }
      operator           = "Any"
      negation_condition = true
    }
  }
  custom_rules {
    name      = "BlockWrongFDID"
    priority  = 20
    rule_type = "MatchRule"
    action    = "Block"
    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "X-Azure-FDID"
      }
      operator           = "Regex"
      negation_condition = true
      match_values       = ["^${azurerm_cdn_frontdoor_profile.lab.resource_guid}$"]
      transforms         = ["Lowercase"]
    }
  }
  custom_rules {
    name      = "BlockRegionalMarker"
    priority  = 30
    rule_type = "MatchRule"
    action    = "Block"
    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "X-Lab-Regional-Block"
      }
      operator     = "Equal"
      match_values = ["1"]
    }
  }
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
