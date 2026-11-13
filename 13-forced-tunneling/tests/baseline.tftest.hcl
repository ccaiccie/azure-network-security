# PLAN ONLY with mock provider. Supplied, NOT RUN. No live provider or deployment.
mock_provider "azurerm" {}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock input only, not a capacity recommendation.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/forced/versions/1.0.0"
}
run "disabled_root" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty-state root creates nothing."
  }
}
run "image_gate" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "origin_gate" {
  command = plan
  variables { origin_access_enabled = true }
  expect_failures = [var.origin_access_enabled]
}
run "nsg_gate" {
  command = plan
  variables { test_paths_enabled = true }
  expect_failures = [var.test_paths_enabled]
}
run "allow_gate" {
  command = plan
  variables { allow_test_flow = true }
  expect_failures = [var.allow_test_flow]
}
run "comparison_gate" {
  command = plan
  variables { source_mode = "firewall_private" }
  expect_failures = [var.source_mode]
}
run "invalid_mode" {
  command = plan
  variables { source_mode = "both" }
  expect_failures = [var.source_mode]
}
run "closed_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = length(azurerm_virtual_network.lab) == 5 && length(azurerm_linux_virtual_machine.vm) == 3 && length(azurerm_virtual_network_peering.transit) == 4 && length(azurerm_virtual_network_peering.management_to_target) == 4 && length(azurerm_virtual_network_peering.target_to_management) == 4
    error_message = "Exact five-VNet, three-VM and twelve-peering topology required."
  }
  assert {
    condition     = local.test_nsg_action == "Deny" && local.origin_nsg_action == "Deny" && local.test_firewall_action == "Deny" && local.source_prefix == "10.20.1.10/32" && toset(azurerm_firewall_policy.lab.private_ip_ranges) == toset(["0.0.0.0/0"])
    error_message = "All exposure gates closed, preserve mode with never-SNAT policy required."
  }
  assert {
    condition     = azurerm_firewall.lab.sku_name == "AZFW_VNet" && azurerm_firewall.lab.sku_tier == "Standard" && one(azurerm_firewall.lab.ip_configuration).public_ip_address_id == null && azurerm_firewall.lab.management_ip_configuration[0].name == "management"
    error_message = "Separate management NIC, no tenant data public IP."
  }
  assert {
    condition     = !azurerm_route_table.app.bgp_route_propagation_enabled && !azurerm_route_table.firewall.bgp_route_propagation_enabled && !azurerm_route_table.perimeter.bgp_route_propagation_enabled && one(azurerm_route_table.app.route).address_prefix == "0.0.0.0/0" && one(azurerm_route_table.firewall.route).address_prefix == "0.0.0.0/0" && one(azurerm_route_table.firewall.route).next_hop_in_ip_address == "10.30.1.4" && one(azurerm_route_table.perimeter.route).address_prefix == "10.20.0.0/16"
    error_message = "App default to F, Firewall default to E, perimeter exact return only."
  }
  assert {
    condition     = azurerm_network_interface.vm["perimeter"].ip_forwarding_enabled && !azurerm_network_interface.vm["app"].ip_forwarding_enabled && !azurerm_network_interface.vm["origin"].ip_forwarding_enabled && one(azurerm_network_interface.vm["app"].ip_configuration).public_ip_address_id == null && alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled])
    error_message = "Only perimeter NIC forwards, app has no public/default-outbound path."
  }
  assert {
    condition     = alltrue([for p in azurerm_virtual_network_peering.transit : p.allow_forwarded_traffic && !p.allow_gateway_transit && !p.use_remote_gateways]) && alltrue([for p in azurerm_virtual_network_peering.management_to_target : !p.allow_forwarded_traffic && !p.allow_gateway_transit && !p.use_remote_gateways])
    error_message = "No gateway sharing or management transit."
  }
  assert {
    condition     = azurerm_firewall_policy_rule_collection_group.forced.priority == 200 && toset(flatten([for c in azurerm_firewall_policy_rule_collection_group.forced.network_rule_collection : [for r in c.rule : "${c.name}|${c.priority}|${c.action}|${r.name}|${join(",", r.destination_ports)}"]])) == toset(["deny-azure-negative|100|Deny|deny-app-8081|8081", "test-flow|200|Deny|app-to-controlled-origin|8080,8082"])
    error_message = "Exact primary and negative network-rule contract."
  }
}
run "diagnostic_envelopes_only" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    private_routes_verified       = true
    perimeter_ready               = true
    origin_access_enabled         = true
    test_paths_enabled            = true
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && local.origin_nsg_action == "Allow" && local.test_firewall_action == "Deny"
    error_message = "Transport envelope opening is independent of Firewall Allow."
  }
}
run "allow_primary_and_perimeter_negative" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    fixtures_ready                = true
    private_routes_verified       = true
    perimeter_ready               = true
    origin_access_enabled         = true
    test_paths_enabled            = true
    allow_test_flow               = true
  }
  assert {
    condition     = local.test_firewall_action == "Allow" && one([for c in azurerm_firewall_policy_rule_collection_group.forced.network_rule_collection : c if c.name == "deny-azure-negative"]).action == "Deny" && one([for n in azurerm_network_security_group.vm["perimeter"].security_rule : n if n.name == "test-restored-return"]).priority == 102
    error_message = "Azure8081 Deny and exact restored-return NSG stay distinct."
  }
}
run "private_snat_mode" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    source_mode                   = "firewall_private"
    snat_comparison_acknowledged  = true
  }
  assert {
    condition     = local.source_prefix == "10.0.1.0/26" && toset(azurerm_firewall_policy.lab.private_ip_ranges) == toset(["IANAPrivateRanges"]) && local.runtime_configs.perimeter.source_mode == "firewall_private" && !var.allow_test_flow && !var.test_paths_enabled && !var.origin_access_enabled
    error_message = "Mode selected FirewallSubnet scope and closed replacement stage."
  }
}
run "closed_retained_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = length(azurerm_linux_virtual_machine.vm) == 3 && local.test_nsg_action == "Deny" && local.origin_nsg_action == "Deny" && local.test_firewall_action == "Deny"
    error_message = "Close policies without deleting management/routes first."
  }
}
