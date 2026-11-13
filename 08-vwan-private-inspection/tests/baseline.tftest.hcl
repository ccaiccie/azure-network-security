# Plan-only mocked-provider tests SUPPLIED, NOT RUN. No live Azure and no apply.
mock_provider "azurerm" {}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock value only; NOT a region/capacity recommendation.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/vwan/versions/1.0.0"
}
run "empty_state_default_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default root must create nothing in empty state."
  }
}
run "deployment_needs_image_attestation" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "closed_topology_contract" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = azurerm_virtual_wan.lab.type == "Standard" && azurerm_virtual_hub.lab.sku == "Standard" && azurerm_virtual_hub.lab.address_prefix == "10.0.0.0/23" && azurerm_firewall.lab.sku_name == "AZFW_Hub" && azurerm_firewall.lab.sku_tier == "Standard"
    error_message = "Managed Standard secured hub required, not AZFW_VNet."
  }
  assert {
    condition     = length(azurerm_virtual_hub_routing_intent.private.routing_policy) == 1 && toset(one(azurerm_virtual_hub_routing_intent.private.routing_policy).destinations) == toset(["PrivateTraffic"]) && !azurerm_virtual_hub_connection.app.internet_security_enabled && !azurerm_virtual_hub_connection.backend.internet_security_enabled
    error_message = "Private-only intent; no Internet policy/default-route propagation."
  }
  assert {
    condition     = alltrue([for t in azurerm_route_table.workload : t.bgp_route_propagation_enabled && length(t.route) == 1 && one(t.route).address_prefix == "0.0.0.0/0" && one(t.route).next_hop_type == "None"]) && local.test_nsg_action == "Deny" && local.test_firewall_action == "Deny"
    error_message = "Propagated private steering plus default discard, both gates initially closed."
  }
  assert {
    condition     = toset(keys(azurerm_linux_virtual_machine.vm)) == toset(["app", "backend"]) && alltrue([for v in azurerm_linux_virtual_machine.vm : v.source_image_id == var.image_id && v.disable_password_authentication]) && alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled]) && alltrue([for n in azurerm_network_interface.vm : !n.ip_forwarding_enabled])
    error_message = "Two fixed-image private nonforwarding workloads required."
  }
  assert {
    condition     = length(azurerm_bastion_host.lab) == 2 && alltrue([for b in azurerm_bastion_host.lab : b.sku == "Standard" && b.tunneling_enabled]) && alltrue([for k, s in local.spokes : contains(["10.10.2.0/26", "10.20.2.0/26"], s.bastion)])
    error_message = "Independent local private management required."
  }
  assert {
    condition     = alltrue([for n in azurerm_network_security_group.workload : alltrue([for r in n.security_rule : r.access == "Deny" if contains(["test-forward", "test-reverse-new"], r.name)])]) && local.test_nsg_rules.app[0].source == "10.10.1.10/32" && local.test_nsg_rules.app[0].destination == "10.20.1.20/32" && toset(local.test_nsg_rules.app[0].ports) == toset(["8080", "8081"]) && local.test_nsg_rules.backend[1].ports == ["8082"]
    error_message = "NSG test gates must be exact source-preserving forward/reverse envelopes."
  }
}
run "ready_firewall_deny_baseline" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    private_routes_verified       = true
    test_paths_enabled            = true
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && local.test_firewall_action == "Deny" && alltrue([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : c.action == "Deny"])
    error_message = "Ready baseline must pass NSG test envelope to named Firewall Deny."
  }
}
run "allow_only_primary_tuple" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    private_routes_verified       = true
    test_paths_enabled            = true
    allow_test_flow               = true
  }
  assert {
    condition     = azurerm_firewall_policy_rule_collection_group.private.priority == 200 && length(azurerm_firewall_policy_rule_collection_group.private.network_rule_collection) == 3 && alltrue([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : c.action == (c.name == "test-flow" ? "Allow" : "Deny")])
    error_message = "Only stable primary collection may change action; alternate/reverse remain Deny."
  }
  assert {
    condition     = alltrue([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : length(c.rule) == 1 && toset(one(c.rule).protocols) == toset(["TCP"]) && length(one(c.rule).destination_ports) == 1])
    error_message = "No broad ports or multi-protocol forwarding."
  }
}
run "reject_nsg_without_route_evidence" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    test_paths_enabled            = true
  }
  expect_failures = [var.test_paths_enabled]
}
run "reject_allow_without_nsg_gate" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    private_routes_verified       = true
    allow_test_flow               = true
  }
  expect_failures = [var.allow_test_flow]
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/vwan/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_foreign_image" {
  command = plan
  variables { image_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/vwan/versions/1.0.0" }
  expect_failures = [var.image_id]
}
run "reject_private_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
