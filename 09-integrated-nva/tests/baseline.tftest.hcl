# Plan-only mocked-provider cases SUPPLIED NOT RUN. Not Azure/vendor validation.
mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    # Terraform >=1.11: expose D during plan, without any mocked apply.
    override_during = plan
    defaults = {
      ip_address = "20.40.1.10"
      # Shared synthetic ID is type-valid for downstream NIC/Bastion validation.
      # It is not a deployed-resource identity or an assertion about ownership.
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-partner/providers/Microsoft.Network/publicIPAddresses/mock-public-ip"
    }
  }
  mock_resource "azurerm_virtual_hub" {
    override_during = plan
    defaults = {
      id                     = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-partner/providers/Microsoft.Network/virtualHubs/partner-hub"
      default_route_table_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-partner/providers/Microsoft.Network/virtualHubs/partner-hub/hubRouteTables/defaultRouteTable"
    }
  }
}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock only, not vendor/region compatibility evidence.
  # Public test vector from RFC 8032 section 7.1 TEST 1, SSH wire encoding.
  # Test data only: NEVER authorize this public, universally known key on a VM.
  # No key pair was generated; no private counterpart is included in this package.
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea RFC8032-TEST-ONLY-NEVER-DEPLOY"
  image_id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/partner/versions/1.0.0"
  vendor_profile = {
    "nva_resource_id" : "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/vendor-managed/providers/Microsoft.Network/networkVirtualAppliances/example-nva",
    "hub_resource_id" : "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/inspection-partner/providers/Microsoft.Network/virtualHubs/partner-hub",
    "managed_application_id" : "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/vendor-app/providers/Microsoft.Solutions/applications/example-app",
    "managed_resource_group_id" : "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/vendor-managed",
    "nva_vendor" : "Mock Security NVA",
    "marketplace_publisher" : "mock-publisher",
    "marketplace_offer" : "mock-offer",
    "marketplace_plan" : "mock-security-plan",
    "marketplace_version" : "1.0.0",
    "software_version" : "1.0.0",
    "scale_unit" : "2",
    "management_system_version" : "mock-manager1",
    "integration_kind" : "security",
    "compatibility_reference" : "https://example.invalid/NOT-A-SUPPORTED-VENDOR",
    "policy_package_id" : "operator-selected-package",
    "primary_rule_id" : "operator-primary-8080",
    "alternate_deny_rule_id" : "operator-deny-8081",
    "evidence_reference" : "mock-only-never-deploy"
  }
}
run "default_empty_state_closed" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default root must create nothing in empty state."
  }
}
run "image_attestation_required" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "infrastructure_before_vendor" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    vendor_profile                = null
  }
  assert {
    condition     = length(azurerm_virtual_hub_routing_intent.internet) == 0 && local.test_nsg_action == "Deny" && azurerm_virtual_hub_connection.app.internet_security_enabled && azurerm_virtual_hub.lab.name == "partner-hub" && azurerm_virtual_wan.lab.type == "Standard"
    error_message = "Bootstrap must keep NSGs closed with no vendor reference; app connection is ready to learn default."
  }
  assert {
    condition     = alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled]) && alltrue([for n in azurerm_network_interface.vm : !n.ip_forwarding_enabled]) && length(azurerm_bastion_host.lab) == 2 && alltrue([for b in azurerm_bastion_host.lab : b.sku == "Standard" && b.tunneling_enabled])
    error_message = "No default outbound, forwarding workloads or shared management dependency."
  }
}
run "management_does_not_learn_default" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    vendor_profile                = null
  }
  assert {
    condition     = toset(azurerm_virtual_network.management.address_space) == toset(["10.40.0.0/16"]) && toset(azurerm_subnet.bastion["app"].address_prefixes) == toset(["10.40.2.0/26"]) && azurerm_subnet.bastion["app"].virtual_network_name == "management" && !azurerm_virtual_network_peering.management_to_app.use_remote_gateways && !azurerm_virtual_network_peering.management_to_app.allow_gateway_transit && !azurerm_virtual_network_peering.app_to_management.use_remote_gateways && !azurerm_virtual_network_peering.app_to_management.allow_gateway_transit && !azurerm_virtual_network_peering.management_to_app.allow_forwarded_traffic && !azurerm_virtual_network_peering.app_to_management.allow_forwarded_traffic
    error_message = "Bastion needs independent management VNet without default sharing or forced-tunnel UDR."
  }
}
run "external_vendor_intent_closed" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    vendor_ready                  = true
    enable_internet_intent        = true
  }
  assert {
    condition     = length(azurerm_virtual_hub_routing_intent.internet) == 1 && toset(one(azurerm_virtual_hub_routing_intent.internet[0].routing_policy).destinations) == toset(["Internet"]) && one(azurerm_virtual_hub_routing_intent.internet[0].routing_policy).next_hop == var.vendor_profile.nva_resource_id && local.test_nsg_action == "Deny"
    error_message = "Only Internet policy may reference exact external NVA; NSGs still closed."
  }
}
run "reviewed_exact_test_envelopes" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    vendor_ready                  = true
    enable_internet_intent        = true
    fixtures_ready                = true
    internet_routes_verified      = true
    vendor_deny_policy_verified   = true
    egress_public_ips             = ["20.40.2.10", "20.40.2.11"]
    test_paths_enabled            = true
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && alltrue([for r in azurerm_network_security_group.workload["app"].security_rule : r.direction == "Outbound" && r.source_address_prefix == "10.10.1.10/32" && r.destination_address_prefix == "20.40.1.10/32" && toset(r.destination_port_ranges) == toset(["8080", "8081"]) if r.name == "test-egress"])
    error_message = "Source envelope must use original A and actual allocated public D."
  }
  assert {
    condition     = alltrue([for r in azurerm_network_security_group.workload["origin"].security_rule : r.direction == "Inbound" && toset(r.source_address_prefixes) == toset(["20.40.2.10/32", "20.40.2.11/32"]) && r.destination_address_prefix == "10.30.1.20/32" if r.name == "test-origin-ingress"])
    error_message = "Origin inbound must use complete public E pool and private B after public-NIC mapping."
  }
}
run "deny_open_without_evidence" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    test_paths_enabled            = true
  }
  expect_failures = [var.test_paths_enabled]
}
run "reject_documentation_egress" {
  command = plan
  variables { egress_public_ips = ["198.51.100.80"] }
  expect_failures = [var.egress_public_ips]
}
run "reject_shared_egress" {
  command = plan
  variables { egress_public_ips = ["100.64.0.1"] }
  expect_failures = [var.egress_public_ips]
}
run "reject_multicast_egress" {
  command = plan
  variables { egress_public_ips = ["224.0.0.1"] }
  expect_failures = [var.egress_public_ips]
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/partner/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_private_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
