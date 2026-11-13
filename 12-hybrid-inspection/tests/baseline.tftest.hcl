# Provider-mocked PLAN-ONLY cases supplied, NOT RUN. Never use a live provider.
# This public sentinel is mock input, NOT a generated PSK and NEVER valid for deployment.
mock_provider "azurerm" {}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock-only. No region/capacity recommendation.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/hybrid/versions/1.0.0"
}
run "disabled_root" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty-state root creates nothing."
  }
}
run "deployment_requires_image" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "connections_require_deployment" {
  command = plan
  variables {
    create_connections = true
    vpn_shared_key     = "MOCKONLYNEVERDEPLOYTHISPUBLICSENTINEL"
  }
  expect_failures = [var.create_connections]
}
run "connections_require_operator_key" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = true
  }
  expect_failures = [var.vpn_shared_key]
}
run "reject_invalid_key_format" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = true
    vpn_shared_key                = "mock short"
  }
  expect_failures = [var.vpn_shared_key]
}
run "connection_readiness_requires_connections" {
  command = plan
  variables { connections_ready = true }
  expect_failures = [var.connections_ready]
}
run "test_nsg_requires_readiness" {
  command = plan
  variables { test_paths_enabled = true }
  expect_failures = [var.test_paths_enabled]
}
run "allow_requires_test_envelope" {
  command = plan
  variables { allow_test_flow = true }
  expect_failures = [var.allow_test_flow]
}
run "exact_closed_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = length(azurerm_virtual_network.lab) == 4 && length(azurerm_virtual_network_gateway.lab) == 2 && length(azurerm_virtual_network_gateway_connection.lab) == 0 && length(azurerm_linux_virtual_machine.vm) == 2 && length(azurerm_bastion_host.lab) == 2
    error_message = "Own complete four-VNet/two-gateway/two-VM/two-Bastion substrate without initial connections."
  }
  assert {
    condition     = alltrue([for g in azurerm_virtual_network_gateway.lab : g.type == "Vpn" && g.vpn_type == "RouteBased" && g.sku == "VpnGw1AZ" && g.generation == "Generation1" && !g.active_active && !g.bgp_enabled && length(g.ip_configuration) == 1]) && alltrue([for p in azurerm_public_ip.gateway : p.sku == "Standard" && p.allocation_method == "Static" && toset(p.zones) == toset(["1", "2", "3"])])
    error_message = "Exact active-standby non-BGP AZ gateway and Standard PIP contract required."
  }
  assert {
    condition     = azurerm_route_table.gateway.bgp_route_propagation_enabled && length(azurerm_route_table.gateway.route) == 1 && one(azurerm_route_table.gateway.route).address_prefix == "10.20.0.0/16" && one(azurerm_route_table.gateway.route).next_hop_type == "VirtualAppliance" && azurerm_route_table.branch.bgp_route_propagation_enabled && length(azurerm_route_table.branch.route) == 1 && one(azurerm_route_table.branch.route).address_prefix == "0.0.0.0/0" && one(azurerm_route_table.branch.route).next_hop_type == "None"
    error_message = "GatewaySubnet only spoke steering, propagation enabled; branch workload only default discard, propagation enabled."
  }
  assert {
    condition     = !azurerm_route_table.spoke.bgp_route_propagation_enabled && toset([for r in azurerm_route_table.spoke.route : "${r.address_prefix}|${r.next_hop_type}"]) == toset(["172.16.0.0/16|VirtualAppliance", "0.0.0.0/0|None"])
    error_message = "Spoke explicit return UDR and default discard with propagation disabled."
  }
  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke.allow_gateway_transit && azurerm_virtual_network_peering.hub_to_spoke.allow_forwarded_traffic && !azurerm_virtual_network_peering.hub_to_spoke.use_remote_gateways && azurerm_virtual_network_peering.spoke_to_hub.use_remote_gateways && azurerm_virtual_network_peering.spoke_to_hub.allow_forwarded_traffic && !azurerm_virtual_network_peering.spoke_to_hub.allow_gateway_transit && length(azurerm_virtual_network_peering.management) == 4 && alltrue([for p in azurerm_virtual_network_peering.management : !p.allow_forwarded_traffic && !p.use_remote_gateways && !p.allow_gateway_transit])
    error_message = "Only hub/spoke share VPN gateway; management uses ordinary isolated peerings."
  }
  assert {
    condition     = local.test_nsg_action == "Deny" && local.test_firewall_action == "Deny" && alltrue([for n in azurerm_network_interface.vm : !n.ip_forwarding_enabled && one(n.ip_configuration).public_ip_address_id == null]) && alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled])
    error_message = "No public VM/NIC forwarding/default outbound; exact test paths and primary policy closed."
  }
  assert {
    condition     = one([for r in azurerm_network_security_group.workload["branch"].security_rule : r if r.name == "allow-local-bastion-ssh"]).source_address_prefix == "172.16.250.0/26" && one([for r in azurerm_network_security_group.workload["spoke"].security_rule : r if r.name == "allow-local-bastion-ssh"]).source_address_prefix == "10.40.2.0/26"
    error_message = "SSH must preserve independent local/peered Bastion source paths."
  }
  assert {
    condition     = azurerm_firewall.lab.sku_name == "AZFW_VNet" && azurerm_firewall_policy.lab.sku == "Standard" && azurerm_firewall_policy_rule_collection_group.private.priority == 200 && toset(flatten([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : [for r in c.rule : "${c.name}|${c.priority}|${c.action}|${r.name}|${join(",", r.destination_ports)}"]])) == toset(["deny-healthy-alternate|100|Deny|deny-branch-alt-8081|8081", "deny-reverse-new|110|Deny|deny-spoke-new-8082|8082", "test-flow|200|Deny|branch-to-spoke-8080|8080"])
    error_message = "Only exact named network rules; both negatives and initial primary Deny."
  }
}
run "both_owned_connections" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = true
    vpn_shared_key                = "MOCKONLYNEVERDEPLOYTHISPUBLICSENTINEL"
  }
  assert {
    condition     = toset(keys(azurerm_virtual_network_gateway_connection.lab)) == toset(["hub-to-branch", "branch-to-hub"]) && alltrue([for c in azurerm_virtual_network_gateway_connection.lab : c.type == "Vnet2Vnet" && !c.bgp_enabled && c.routing_weight == 10]) && local.test_nsg_action == "Deny" && local.test_firewall_action == "Deny"
    error_message = "Both reciprocal connections, no BGP/NAT, test paths still closed."
  }
}
run "closed_policy_diagnostic" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = true
    vpn_shared_key                = "MOCKONLYNEVERDEPLOYTHISPUBLICSENTINEL"
    connections_ready             = true
    fixtures_ready                = true
    private_routes_verified       = true
    test_paths_enabled            = true
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && local.test_firewall_action == "Deny" && alltrue([for n in azurerm_network_security_group.workload : alltrue([for rule in n.security_rule : rule.access == "Allow" if contains([100, 101], rule.priority)])])
    error_message = "Exact NSG envelopes must open independently of primary Firewall Allow for valid denial attribution."
  }
}
run "primary_allow_only" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = true
    vpn_shared_key                = "MOCKONLYNEVERDEPLOYTHISPUBLICSENTINEL"
    connections_ready             = true
    fixtures_ready                = true
    private_routes_verified       = true
    test_paths_enabled            = true
    allow_test_flow               = true
  }
  assert {
    condition     = one([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : c if c.name == "test-flow"]).action == "Allow" && alltrue([for c in azurerm_firewall_policy_rule_collection_group.private.network_rule_collection : c.action == "Deny" if c.name != "test-flow"])
    error_message = "Primary8080 only becomes Allow; alternate8081 and independent reverse8082 remain Deny."
  }
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/hybrid/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_foreign_image" {
  command = plan
  variables { image_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/hybrid/versions/1.0.0" }
  expect_failures = [var.image_id]
}
run "reject_key_while_connections_disabled" {
  command = plan
  variables { vpn_shared_key = "MOCKONLYNEVERDEPLOYTHISPUBLICSENTINEL" }
  expect_failures = [var.vpn_shared_key]
}
run "reject_stale_readiness_during_connection_removal" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    create_connections            = false
    connections_ready             = true
    vpn_shared_key                = null
  }
  expect_failures = [var.connections_ready]
}
run "isolated_connection_removal_configuration" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    allow_test_flow               = false
    test_paths_enabled            = false
    fixtures_ready                = false
    private_routes_verified       = false
    connections_ready             = false
    create_connections            = false
    vpn_shared_key                = null
  }
  assert {
    condition     = length(azurerm_virtual_network_gateway_connection.lab) == 0 && length(azurerm_virtual_network_gateway.lab) == 2 && length(azurerm_bastion_host.lab) == 2 && local.test_nsg_action == "Deny" && local.test_firewall_action == "Deny" && length(azurerm_route_table.gateway.route) == 1 && length(azurerm_route_table.spoke.route) == 2
    error_message = "Isolated removal configuration must omit connections while keeping closed policy, routes, gateways and private management. This is not a tested deletion from existing state."
  }
}
