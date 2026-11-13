# Mock-provider PLAN ONLY cases, supplied NOT RUN. No live cloud operation.
mock_provider "azurerm" {
  mock_resource "azurerm_cdn_frontdoor_profile" {
    defaults = { resource_guid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  }
  mock_resource "azurerm_linux_web_app" {
    defaults = { default_hostname = "offline-backend.azurewebsites.net" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { ip_address = "8.8.8.8" }
  }
}
variables {
  subscription_id              = "11111111-2222-3333-4444-555555555555"
  location                     = "westeurope" # Mock input only, not a region recommendation.
  backend_name                 = "offline-backend"
  edge_endpoint_name           = "offline-edge"
  origin_fqdn                  = "origin.lab.example.com"
  operator_cidr                = "8.8.4.4/32" # Synthetic test input, never contacted.
  gateway_identity_id          = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/approved"
  listener_key_vault_secret_id = "https://approved-vault.vault.azure.net/secrets/approved-origin-cert"
}
run "disabled_root" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "False root creates no resources in empty state."
  }
}
run "reject_unready_deploy_lab" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "reject_unready_origin_dns_verified" {
  command = plan
  variables { origin_dns_verified = true }
  expect_failures = [var.origin_dns_verified]
}
run "reject_unready_fixture_publish_enabled" {
  command = plan
  variables { fixture_publish_enabled = true }
  expect_failures = [var.fixture_publish_enabled]
}
run "reject_unready_fixture_ready" {
  command = plan
  variables { fixture_ready = true }
  expect_failures = [var.fixture_ready]
}
run "reject_unready_backend_access_enabled" {
  command = plan
  variables { backend_access_enabled = true }
  expect_failures = [var.backend_access_enabled]
}
run "reject_unready_backend_health_verified" {
  command = plan
  variables { backend_health_verified = true }
  expect_failures = [var.backend_health_verified]
}
run "reject_unready_gateway_ingress_enabled" {
  command = plan
  variables { gateway_ingress_enabled = true }
  expect_failures = [var.gateway_ingress_enabled]
}
run "reject_unready_fdid_diagnostic_ingress_enabled" {
  command = plan
  variables { fdid_diagnostic_ingress_enabled = true }
  expect_failures = [var.fdid_diagnostic_ingress_enabled]
}
run "reject_unready_fdid_negative_cases_verified" {
  command = plan
  variables { fdid_negative_cases_verified = true }
  expect_failures = [var.fdid_negative_cases_verified]
}
run "reject_unready_edge_route_enabled" {
  command = plan
  variables { edge_route_enabled = true }
  expect_failures = [var.edge_route_enabled]
}
run "closed_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                   = true
    certificate_access_confirmed = true
  }
  assert {
    condition     = azurerm_network_security_rule.frontdoor.access == "Deny" && azurerm_network_security_rule.diagnostic.access == "Deny" && !azurerm_cdn_frontdoor_route.lab.enabled
    error_message = "Initial user paths are closed, without disabling platform control traffic."
  }
  assert {
    condition     = one(azurerm_linux_web_app.backend.site_config).ip_restriction_default_action == "Deny" && length(one(azurerm_linux_web_app.backend.site_config).ip_restriction) == 0 && one(azurerm_linux_web_app.backend.site_config).scm_ip_restriction_default_action == "Deny" && length(one(azurerm_linux_web_app.backend.site_config).scm_ip_restriction) == 0
    error_message = "Both frontend and SCM start unmatched Deny without exceptions."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.edge.mode == "Prevention" && one(azurerm_web_application_firewall_policy.gateway.policy_settings).mode == "Prevention" && alltrue([for r in azurerm_web_application_firewall_policy.gateway.custom_rules : r.action == "Block"])
    error_message = "Policies stay Prevention; no custom Allow bypass."
  }
  assert {
    condition     = one(azurerm_application_gateway.lab.ssl_certificate).key_vault_secret_id == var.listener_key_vault_secret_id && one(azurerm_application_gateway.lab.identity).type == "UserAssigned" && one(azurerm_application_gateway.lab.http_listener).require_sni
    error_message = "Existing certificate reference/identity and required origin SNI only."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_origin.gateway.certificate_name_check_enabled && azurerm_cdn_frontdoor_route.lab.forwarding_protocol == "HttpsOnly" && length(azurerm_cdn_frontdoor_route.lab.cache) == 0
    error_message = "Origin TLS verification/HTTPS and no route caching."
  }
  assert {
    condition     = one(azurerm_application_gateway.lab.backend_http_settings).protocol == "Https" && one(azurerm_application_gateway.lab.probe).path == "/health" && one(azurerm_application_gateway.lab.probe).protocol == "Https"
    error_message = "Independent third TLS leg and explicit backend probe."
  }
  assert {
    condition     = azurerm_subnet.gateway.address_prefixes == tolist(["10.60.1.0/24"]) && azurerm_network_security_rule.manager.destination_port_range == "65200-65535" && azurerm_network_security_rule.platform_probe.source_address_prefix == "AzureLoadBalancer"
    error_message = "Dedicated subnet and platform exceptions retained."
  }
}
run "diagnostic_only" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                      = true
    certificate_access_confirmed    = true
    origin_dns_verified             = true
    fixture_ready                   = true
    backend_access_enabled          = true
    backend_health_verified         = true
    diagnostic_ingress_authorized   = true
    fdid_diagnostic_ingress_enabled = true
  }
  assert {
    condition     = azurerm_network_security_rule.diagnostic.access == "Allow" && azurerm_network_security_rule.diagnostic.source_address_prefix == var.operator_cidr && !azurerm_cdn_frontdoor_route.lab.enabled && length(one(azurerm_linux_web_app.backend.site_config).scm_ip_restriction) == 0
    error_message = "Only exact diagnostic client opens while edge/SCM remain closed."
  }
}
run "published_edge" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                   = true
    certificate_access_confirmed = true
    origin_dns_verified          = true
    fixture_ready                = true
    backend_access_enabled       = true
    backend_health_verified      = true
    gateway_ingress_enabled      = true
    fdid_negative_cases_verified = true
    edge_route_enabled           = true
  }
  assert {
    condition     = azurerm_cdn_frontdoor_route.lab.enabled && azurerm_network_security_rule.frontdoor.access == "Allow" && azurerm_network_security_rule.diagnostic.access == "Deny" && length(one(azurerm_linux_web_app.backend.site_config).scm_ip_restriction) == 0
    error_message = "Published baseline retains exact source tag and no diagnostic/SCM exception."
  }
}
run "reject_nonpublic_client" {
  command = plan
  variables { operator_cidr = "192.0.2.10/32" }
  expect_failures = [var.operator_cidr]
}
run "reject_versioned_secret_reference" {
  command = plan
  variables { listener_key_vault_secret_id = "https://approved-vault.vault.azure.net/secrets/approved-cert/11111111111111111111111111111111" }
  expect_failures = [var.listener_key_vault_secret_id]
}
