# Provider-mocked PLAN ONLY, supplied NOT RUN. No live provider/deployment.
mock_provider "azurerm" {}
variables {
  subscription_id      = "11111111-1111-1111-1111-111111111111"
  location             = "westeurope" # Mock only, not a capacity recommendation.
  ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  storage_account_name = "peoffline123"
  image_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/images/providers/Microsoft.Compute/galleries/approved/images/pe/versions/1.0.0"
}
run "disabled_root" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "False root creates nothing in empty state."
  }
}
run "reject_unready_deploy_lab" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "reject_unready_dns_enabled" {
  command = plan
  variables { dns_enabled = true }
  expect_failures = [var.dns_enabled]
}
run "reject_unready_pe_ingress_enabled" {
  command = plan
  variables { pe_ingress_enabled = true }
  expect_failures = [var.pe_ingress_enabled]
}
run "reject_unready_client_paths_enabled" {
  command = plan
  variables { client_paths_enabled = true }
  expect_failures = [var.client_paths_enabled]
}
run "reject_unready_seed_paths_enabled" {
  command = plan
  variables { seed_paths_enabled = true }
  expect_failures = [var.seed_paths_enabled]
}
run "reject_unready_allow_client_blob" {
  command = plan
  variables { allow_client_blob = true }
  expect_failures = [var.allow_client_blob]
}
run "reject_unready_allow_seed_blob" {
  command = plan
  variables { allow_seed_blob = true }
  expect_failures = [var.allow_seed_blob]
}
run "reject_unready_grant_reader_role" {
  command = plan
  variables { grant_reader_role = true }
  expect_failures = [var.grant_reader_role]
}
run "reject_unready_grant_seed_role" {
  command = plan
  variables { grant_seed_role = true }
  expect_failures = [var.grant_seed_role]
}
run "reject_live_policy_disable" {
  command = plan
  variables { pe_network_policies = "Disabled" }
  expect_failures = [var.pe_network_policies]
}
run "reject_unisolated_route_removal" {
  command = plan
  variables { install_pe_host_route = false }
  expect_failures = [var.install_pe_host_route]
}
run "closed_owned_substrate" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    identity_access_authorized    = true
  }
  assert {
    condition     = length(azurerm_virtual_network.lab) == 4 && length(azurerm_virtual_network_peering.lab) == 8 && length(azurerm_linux_virtual_machine.client) == 2 && length(azurerm_role_assignment.blob) == 0
    error_message = "Four VNets, real direct competitor, separate identities and no initial grants."
  }
  assert {
    condition     = azurerm_subnet.endpoint.private_endpoint_network_policies == "Enabled" && one(azurerm_private_endpoint.blob.ip_configuration).private_ip_address == "10.30.1.7" && one(azurerm_private_endpoint.blob.ip_configuration).subresource_name == "blob" && one(azurerm_private_endpoint.blob.ip_configuration).member_name == "blob"
    error_message = "Exact static Blob PE and both network policies."
  }
  assert {
    condition     = toset([for route in azurerm_route_table.client.route : "${route.address_prefix}|${route.next_hop_type}"]) == toset(["10.30.1.7/32|VirtualAppliance", "0.0.0.0/0|None"]) && !azurerm_route_table.client.bgp_route_propagation_enabled
    error_message = "Only client PE host route to F and closed other default."
  }
  assert {
    condition     = azurerm_storage_account.lab.public_network_access == "Disabled" && !azurerm_storage_account.lab.shared_access_key_enabled && !azurerm_storage_account.lab.allow_nested_items_to_be_public && azurerm_storage_account.lab.https_traffic_only_enabled && azurerm_storage_container.lab.container_access_type == "private"
    error_message = "Private service, no Shared Key/anonymous/public bootstrap."
  }
  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.hub.resolution_policy == "Default" && !azurerm_private_dns_zone_virtual_network_link.hub.registration_enabled && azurerm_firewall_policy.lab.dns[0].proxy_enabled
    error_message = "Hub private zone, no public fallback, Firewall DNS proxy."
  }
  assert {
    condition     = alltrue([for c in azurerm_firewall_policy_rule_collection_group.blob.application_rule_collection : c.action == "Deny"]) && length(azurerm_firewall_policy_rule_collection_group.blob.network_rule_collection) == 0 && alltrue([for n in azurerm_network_interface.client : !n.ip_forwarding_enabled && one(n.ip_configuration).public_ip_address_id == null])
    error_message = "No terminating network443 Allow, no public/forwarding clients, apps closed."
  }
}
run "platform_imds_without_data_grants" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    identity_access_authorized    = true
  }
  assert {
    condition     = alltrue([for n in azurerm_network_security_group.client : one([for rule in n.security_rule : rule if rule.name == "platform-imds"]).access == "Allow"]) && length(azurerm_role_assignment.blob) == 0 && local.app_actions.reader == "Deny" && local.app_actions.seed == "Deny"
    error_message = "Host-local IMDS boot access is separate from Blob authorization and network Allow."
  }
}
run "seed_only_stage" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    identity_access_authorized    = true
    pe_ready                      = true
    dns_enabled                   = true
    dns_verified                  = true
    routes_verified               = true
    pe_ingress_enabled            = true
    seed_paths_enabled            = true
    grant_seed_role               = true
    allow_seed_blob               = true
  }
  assert {
    condition     = toset(keys(azurerm_role_assignment.blob)) == toset(["seed"]) && azurerm_role_assignment.blob["seed"].role_definition_name == "Storage Blob Data Contributor" && azurerm_role_assignment.blob["seed"].scope == azurerm_storage_container.lab.id && local.app_actions.reader == "Deny" && local.client_actions.reader == "Deny"
    error_message = "Writer lives only on separate seed VM at container scope."
  }
}
run "reader_stage_seed_closed" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    identity_access_authorized    = true
    pe_ready                      = true
    dns_enabled                   = true
    dns_verified                  = true
    routes_verified               = true
    pe_ingress_enabled            = true
    client_paths_enabled          = true
    grant_reader_role             = true
    allow_client_blob             = true
  }
  assert {
    condition     = toset(keys(azurerm_role_assignment.blob)) == toset(["reader"]) && azurerm_role_assignment.blob["reader"].role_definition_name == "Storage Blob Data Reader" && local.app_actions.seed == "Deny" && local.client_actions.seed == "Deny"
    error_message = "Reader scope separate from closed and revoked seeder."
  }
}
run "isolated_disabled_policy_observation" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    identity_access_authorized    = true
    route_experiment_acknowledged = true
    isolation_verified            = true
    pe_network_policies           = "Disabled"
    install_pe_host_route         = false
  }
  assert {
    condition     = azurerm_subnet.endpoint.private_endpoint_network_policies == "Disabled" && length(azurerm_route_table.client.route) == 1 && alltrue([for c in azurerm_firewall_policy_rule_collection_group.blob.application_rule_collection : c.action == "Deny"]) && local.client_actions.reader == "Deny" && local.client_actions.seed == "Deny"
    error_message = "Only isolated configuration observation; never a live bypass flow."
  }
}
