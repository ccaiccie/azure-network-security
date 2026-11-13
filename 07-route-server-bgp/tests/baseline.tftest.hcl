# Plan-only mocked provider cases, SUPPLIED NOT RUN. No Azure/apply.
mock_provider "azurerm" {
  mock_resource "azurerm_route_server" {
    defaults = {
      virtual_router_ips = ["10.0.1.4", "10.0.1.5"]
      virtual_router_asn = 65515
      routing_state      = "Provisioned"
    }
  }
}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock input, not a recommendation or capacity finding.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/rs/versions/1.0.0"
  frr_version     = "10.4"
}
run "root_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty-state root must create no resources."
  }
}
run "deployment_requires_image_attestation" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "isolated_route_server_contract" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = azurerm_route_server.lab.name == "routeserver" && azurerm_route_server.lab.sku == "Standard" && !azurerm_route_server.lab.branch_to_branch_traffic_enabled && azurerm_route_server.lab.hub_routing_preference == "ASPath" && toset(azurerm_subnet.routeserver.address_prefixes) == toset(["10.0.1.0/26"])
    error_message = "Dedicated /26 and isolated Standard RS with AS-path preference required."
  }
  assert {
    condition     = toset(keys(azurerm_route_server_bgp_connection.nva)) == toset(["nva1", "nva2"]) && alltrue([for p in azurerm_route_server_bgp_connection.nva : p.peer_asn == 65010])
    error_message = "Two Azure connection objects must describe two NVA peers. Guest four-session behavior remains source/runtime checked."
  }
  assert {
    condition     = azurerm_route_table.spoke["app"].bgp_route_propagation_enabled && !azurerm_route_table.spoke["remote"].bgp_route_propagation_enabled && !azurerm_route_table.nva.bgp_route_propagation_enabled && alltrue([for t in azurerm_route_table.spoke : length(t.route) == 1 && one(t.route).address_prefix == "0.0.0.0/0" && one(t.route).next_hop_type == "None"]) && length(azurerm_route_table.nva.route) == 1 && one(azurerm_route_table.nva.route).next_hop_type == "None"
    error_message = "Only app propagates BGP; substrate tables must not recurse to the NVA or replace exact /24 learning."
  }
  assert {
    condition     = azurerm_virtual_network_peering.hub_to_app.allow_gateway_transit && azurerm_virtual_network_peering.app_to_hub.use_remote_gateways && !azurerm_virtual_network_peering.hub_to_remote.allow_gateway_transit && !azurerm_virtual_network_peering.remote_to_hub.use_remote_gateways && alltrue([for nic_name, nic in azurerm_network_interface.vm : nic.ip_forwarding_enabled == contains(["nva1", "nva2"], nic_name)])
    error_message = "App-only RS sharing and NVA-only NIC forwarding required."
  }
  assert {
    condition     = local.destination_prefix == "172.20.50.0/24" && local.destination_ip == "172.20.50.10" && toset(azurerm_virtual_network.hub.address_space) == toset(["10.0.0.0/16"]) && local.spokes.app.cidr == "10.10.0.0/16" && local.spokes.remote.cidr == "10.30.0.0/16" && local.private_ips.remote == "10.30.1.20"
    error_message = "Synthetic destination must not be an Azure VNet prefix or fake NIC IP."
  }
  assert {
    condition     = local.nsg_service_rules.app[0].destination == "172.20.50.10/32" && toset(local.nsg_service_rules.app[0].destination_ports) == toset(["8080", "8081"]) && alltrue([for node in ["nva1", "nva2"] : local.nsg_service_rules[node][0].source == "10.10.1.10/32" && local.nsg_service_rules[node][1].source == "172.20.50.10/32" && local.nsg_service_rules[node][2].protocol == "*" && local.nsg_service_rules[node][3].protocol == "*"])
    error_message = "Original/restored test tuples and honestly wildcard-protocol outer envelopes required."
  }
  assert {
    condition     = azurerm_bastion_host.lab.sku == "Standard" && azurerm_bastion_host.lab.tunneling_enabled && alltrue([for s in azurerm_subnet.spoke : !s.default_outbound_access_enabled]) && !azurerm_subnet.nva.default_outbound_access_enabled && alltrue([for vm in azurerm_linux_virtual_machine.vm : vm.source_image_id == var.image_id && vm.disable_password_authentication])
    error_message = "Private workload management, no default egress, and approved exact image required."
  }
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/rs/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_foreign_image" {
  command = plan
  variables { image_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/rs/versions/1.0.0" }
  expect_failures = [var.image_id]
}
run "reject_unreviewed_frr_family" {
  command = plan
  variables { frr_version = "9.1" }
  expect_failures = [var.frr_version]
}
run "reject_unpinned_frr" {
  command = plan
  variables { frr_version = "latest" }
  expect_failures = [var.frr_version]
}
run "reject_private_ssh_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
run "reject_bad_subscription" {
  command = plan
  variables { subscription_id = "not-a-subscription" }
  expect_failures = [var.subscription_id, var.image_id]
}
