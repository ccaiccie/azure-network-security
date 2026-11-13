# Mock-provider PLAN cases SUPPLIED NOT RUN; no live provider or Azure test.
mock_provider "azurerm" {
  # Plan-only NSG assertions require known destination addresses. Other resource
  # types retain ordinary unknown computed values. This is never a real address
  # allocation or provider request, and does not exercise public-IP uniqueness.
  mock_resource "azurerm_public_ip" {
    override_during = plan
    defaults = {
      id         = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-spp/providers/Microsoft.Network/publicIPAddresses/mock-public-ip"
      ip_address = "192.0.2.10"
    }
  }
}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock only; not supported SPP region evidence.
  # Published PUBLIC test-vector bytes from RFC8032 section7.1 TEST1, encoded
  # in OpenSSH wire format. No key was generated; NEVER use this for access.
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea RFC8032-TEST-ONLY-NEVER-DEPLOY"
  image_id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/spp/versions/1.0.0"
  provider_profile = {
    "provider" : "ZScaler",
    "zia_cloud" : "mock-cloud",
    "tenant_reference" : "mock-tenant",
    "location_reference" : "mock-location",
    "license_reference" : "mock-license-reference-not-a-license",
    "compatibility_reference" : "https://example.invalid/mock-support",
    "azure_application_id" : "22222222-2222-2222-2222-222222222222",
    "azure_principal_object_id" : "33333333-3333-3333-3333-333333333333",
    "approved_scope" : "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-spp",
    "approved_role_reference" : "mock-approved-role",
    "grant_expiry_reference" : "mock-expiry",
    "routing_owner_reference" : "mock-supported-owner",
    "primary_category_reference" : "mock-D1-category",
    "alternate_category_reference" : "mock-D2-category",
    "primary_rule_reference" : "mock-primary-rule",
    "alternate_block_rule_reference" : "mock-alternate-block",
    "policy_activation_reference" : "mock-activation",
    "evidence_reference" : "MOCK-ONLY-NOT-A-REAL-PROFILE"
  }
}
run "default_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty-state root creates nothing."
  }
}
run "reject_unconfirmed_image" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "isolated_owned_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    provider_profile              = null
  }
  assert {
    condition     = length(azurerm_virtual_hub_security_partner_provider.lab) == 0 && !azurerm_virtual_hub_connection.app.internet_security_enabled && local.test_nsg_action == "Deny" && azurerm_vpn_gateway.lab.scale_unit == 1 && azurerm_virtual_hub.lab.address_prefix == "10.0.0.0/23"
    error_message = "Gateway exists before SPP; source default and test envelopes closed."
  }
  assert {
    condition     = toset(keys(azurerm_linux_virtual_machine.vm)) == toset(["app", "origin1", "origin2"]) && length(azurerm_public_ip.origin) == 2 && length(azurerm_bastion_host.lab) == 2 && alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled])
    error_message = "Three controlled private-address VMs, two owned public origins and two protected Bastions required."
  }
}
run "spp_without_source_default" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    enable_spp                    = true
  }
  assert {
    condition     = length(azurerm_virtual_hub_security_partner_provider.lab) == 1 && azurerm_virtual_hub_security_partner_provider.lab[0].security_provider_name == "ZScaler" && !azurerm_virtual_hub_connection.app.internet_security_enabled && local.test_nsg_action == "Deny"
    error_message = "Azure SPP association is not external onboarding or traffic readiness."
  }
}
run "source_opt_in_after_external_transport" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    enable_spp                    = true
    provider_onboarding_verified  = true
    tunnels_verified              = true
    provider_routing_configured   = true
    enable_source_default         = true
  }
  assert {
    condition     = azurerm_virtual_hub_connection.app.internet_security_enabled && local.test_nsg_action == "Deny"
    error_message = "Default opt-in precedes endpoint NSG opening, not vice versa."
  }
}
run "reject_default_without_tunnel_evidence" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    enable_spp                    = true
    provider_onboarding_verified  = true
    provider_routing_configured   = true
    enable_source_default         = true
  }
  expect_failures = [var.enable_source_default]
}
run "reject_open_without_readiness" {
  command = plan
  variables { test_paths_enabled = true }
  expect_failures = [var.test_paths_enabled]
}
run "management_outside_protected_default" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = toset(azurerm_virtual_network.management.address_space) == toset(["10.40.0.0/16"]) && azurerm_subnet.bastion["app"].virtual_network_name == "management" && !azurerm_virtual_network_peering.management_to_app.use_remote_gateways && !azurerm_virtual_network_peering.management_to_app.allow_gateway_transit && !azurerm_virtual_network_peering.management_to_app.allow_forwarded_traffic && !azurerm_virtual_network_peering.app_to_management.use_remote_gateways && !azurerm_virtual_network_peering.app_to_management.allow_gateway_transit && !azurerm_virtual_network_peering.app_to_management.allow_forwarded_traffic
    error_message = "Independent peered management with no inherited default or forwarded transit."
  }
}
run "reject_documentation_pool" {
  command = plan
  variables { egress_public_ips = ["198.51.100.80"] }
  expect_failures = [var.egress_public_ips]
}
run "reject_multicast_pool" {
  command = plan
  variables { egress_public_ips = ["224.0.0.1"] }
  expect_failures = [var.egress_public_ips]
}
run "reject_bad_gateway_scale" {
  command = plan
  variables { vpn_scale_unit = 0 }
  expect_failures = [var.vpn_scale_unit]
}
run "reject_private_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
run "reviewed_http_envelopes_only" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                     = true
    image_prerequisites_confirmed  = true
    enable_spp                     = true
    provider_onboarding_verified   = true
    tunnels_verified               = true
    provider_routing_configured    = true
    enable_source_default          = true
    protected_routes_verified      = true
    fixtures_ready                 = true
    provider_block_policy_verified = true
    test_paths_enabled             = true
    egress_public_ips              = ["20.40.2.10", "20.40.2.11"]
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && one([for r in azurerm_network_security_group.workload["app"].security_rule : r if r.name == "test-web-egress"]).source_address_prefix == "10.10.1.10/32" && alltrue([for n in azurerm_network_security_group.workload : one([for r in n.security_rule : r if r.priority == 100]).destination_port_range == "80"])
    error_message = "Only original app source and exact HTTP80 endpoint envelopes may open."
  }
  assert {
    condition     = alltrue([for role in ["origin1", "origin2"] : toset(one([for r in azurerm_network_security_group.workload[role].security_rule : r if r.name == "test-web-ingress"]).source_address_prefixes) == toset(["20.40.2.10/32", "20.40.2.11/32"])])
    error_message = "Both origins must allow only the complete reviewed provider E pool."
  }
}
