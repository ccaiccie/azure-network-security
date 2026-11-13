# Supplied plan-only mock tests. NOT RUN here: Terraform/provider are unavailable.
# Fake identifiers and reserved documentation SSH material are local mock inputs,
# never deployment values or authorization. No apply run is present.
mock_provider "azurerm" {}

variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_version   = "24.04.202610010"
  operator_cidr   = "9.9.9.9/32" # Mock public-shape input only; no probe to this address.
  origin_name     = "mock-origin-never-deploy"
}

run "default_creates_nothing" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && output.deployment_enabled == false
    error_message = "Root must create no lab by default."
  }
}
run "closed_infrastructure" {
  command = plan
  module { source = "./module" }
  variables { deploy_lab = true }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.tls) == 0
    error_message = "Closed infrastructure must have no application allow group."
  }
  assert {
    condition     = length(azurerm_firewall_policy.lab.tls_certificate) == 0 && length(azurerm_firewall_policy.lab.identity) == 0
    error_message = "No CA or identity linkage when disabled."
  }
  assert {
    condition     = azurerm_firewall.lab.sku_tier == "Premium" && azurerm_firewall_policy.lab.intrusion_detection[0].mode == "Deny" && azurerm_firewall_policy.lab.threat_intelligence_mode == "Alert"
    error_message = "Premium/IDPS/TI configuration mismatch."
  }
  assert {
    condition     = one(azurerm_route_table.app.route).address_prefix == "0.0.0.0/0" && one(azurerm_route_table.app.route).next_hop_type == "VirtualAppliance"
    error_message = "App must have default VirtualAppliance UDR. F next-hop reference is source-checked separately."
  }
  assert {
    condition     = azurerm_subnet.app.default_outbound_access_enabled == false && azurerm_network_interface.app.ip_configuration[0].private_ip_address == "10.10.1.10"
    error_message = "Private client addressing/default egress mismatch."
  }
  assert {
    condition     = local.app_nsg_rules["allow-https-to-internet"].source == "10.10.1.10/32" && local.app_nsg_rules["allow-https-to-internet"].destination == "Internet" && local.app_nsg_rules["allow-https-to-internet"].port == "443" && local.app_nsg_rules["allow-https-to-internet"].protocol == "Tcp" && local.app_nsg_rules["allow-https-to-internet"].priority == 110
    error_message = "NSG HTTPS envelope changed."
  }
  assert {
    condition     = local.app_nsg_rules["deny-direct-platform-dns"].destination == "AzurePlatformDNS" && local.app_nsg_rules["deny-direct-platform-dns"].access == "Deny" && local.app_nsg_rules["deny-other-outbound"].priority == 4000 && local.app_nsg_rules["deny-other-inbound"].access == "Deny"
    error_message = "NSG default/alternate DNS closures changed."
  }
  assert {
    condition     = local.app_nsg_rules["allow-bastion-ssh"].source == "10.0.2.0/26" && local.app_nsg_rules["allow-bastion-ssh"].port == "22" && azurerm_bastion_host.lab.sku == "Standard" && azurerm_bastion_host.lab.tunneling_enabled
    error_message = "Private Bastion management contract changed."
  }
  assert {
    condition     = azurerm_linux_web_app.origin.https_only && !azurerm_linux_web_app.origin.ftp_publish_basic_authentication_enabled && !azurerm_linux_web_app.origin.webdeploy_publish_basic_authentication_enabled && azurerm_linux_web_app.origin.site_config[0].scm_ip_restriction_default_action == "Deny" && !azurerm_linux_web_app.origin.site_config[0].scm_use_main_ip_restriction
    error_message = "Origin publishing/access envelope changed."
  }
}
run "approved_ca_without_origin_stays_closed" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                  = true
    enable_tls_inspection       = true
    tls_prerequisites_confirmed = true
    tls_secret_uri              = "https://mockvault.vault.azure.net/secrets/mock-intermediate/11111111111111111111111111111111"
    tls_identity_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mock-pki/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.tls) == 0 && length(azurerm_firewall_policy.lab.tls_certificate) == 1
    error_message = "CA linkage alone must not open workload egress."
  }
}
run "ready_policy_contract" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                  = true
    enable_tls_inspection       = true
    tls_prerequisites_confirmed = true
    origin_fixture_ready        = true
    tls_secret_uri              = "https://mockvault.vault.azure.net/secrets/mock-intermediate/11111111111111111111111111111111"
    tls_identity_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mock-pki/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
  assert {
    condition     = one(azurerm_firewall_policy_rule_collection_group.tls).name == "test-rules" && one(azurerm_firewall_policy_rule_collection_group.tls).priority == 200
    error_message = "Application group contract changed."
  }
  assert {
    condition     = alltrue([for c in one(azurerm_firewall_policy_rule_collection_group.tls).application_rule_collection : (c.name == "deny-test-url" && c.priority == 100 && c.action == "Deny") || (c.name == "allow-test-origin" && c.priority == 200 && c.action == "Allow")]) && length(one(azurerm_firewall_policy_rule_collection_group.tls).application_rule_collection) == 2
    error_message = "Exactly the ordered deny/allow collections are required."
  }
  assert {
    condition     = alltrue(flatten([for c in one(azurerm_firewall_policy_rule_collection_group.tls).application_rule_collection : [for r in c.rule : r.terminate_tls && toset(r.source_addresses) == toset(["10.10.1.10/32"]) && alltrue([for p in r.protocols : p.type == "Https" && p.port == 443])]]))
    error_message = "All rules must be inspected HTTPS443 from A/32."
  }
  assert {
    condition     = length(one(azurerm_firewall_policy_rule_collection_group.tls).network_rule_collection) == 0 && length(one(azurerm_firewall_policy_rule_collection_group.tls).nat_rule_collection) == 0
    error_message = "No network or NAT collection may bypass the app test."
  }
}
run "reject_inspection_without_approval" {
  command = plan
  variables { enable_tls_inspection = true }
  expect_failures = [var.enable_tls_inspection, var.tls_secret_uri, var.tls_identity_id]
}
run "reject_ready_without_inspection" {
  command = plan
  variables { origin_fixture_ready = true }
  expect_failures = [var.origin_fixture_ready]
}
run "reject_latest_image" {
  command = plan
  variables { image_version = "latest" }
  expect_failures = [var.image_version]
}
run "reject_broad_operator" {
  command = plan
  variables { operator_cidr = "9.9.9.0/24" }
  expect_failures = [var.operator_cidr]
}
run "reject_documentation_operator" {
  command = plan
  variables { operator_cidr = "203.0.113.10/32" }
  expect_failures = [var.operator_cidr]
}
run "reject_non_uri_secret_input_even_disabled" {
  command = plan
  variables { tls_secret_uri = "not-a-secret-uri" }
  expect_failures = [var.tls_secret_uri]
}
run "reject_foreign_identity_even_disabled" {
  command = plan
  variables { tls_identity_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/mock-pki/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity" }
  expect_failures = [var.tls_identity_id]
}
