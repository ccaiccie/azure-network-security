# Optional provider-mocked plan-only tests; never replace with a live provider.
mock_provider "azurerm" {}
variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA offline-test-only"
  image_version   = "0.0.0"
  # Synthetic provider-mock input only. No connection or authorization to this IP.
  allowed_client_cidr = "9.9.9.9/32"
}

run "unpublished_default_exact_network" {
  command = plan
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.dnat) == 0 && output.public_http_url == null
    error_message = "Default must not create a publication rule or advertise an active HTTP URL."
  }
  assert {
    condition     = toset([for name, r in local.route_specs : "${name}|${r.prefix}|${r.type}"]) == toset(["default|0.0.0.0/0|VirtualAppliance"])
    error_message = "Baseline must contain only the /0 inspection route; no hub-prefix route."
  }
  assert {
    condition = toset([for name, r in local.backend_nsg_rules : "${name}|${r.priority}|${r.direction}|${r.access}|${r.protocol}|${r.source}|${r.destination}|${r.port}"]) == toset([
      "allow-translated-http|100|Inbound|Allow|Tcp|10.0.1.0/26|10.20.1.10/32|8080",
      "allow-private-ssh|110|Inbound|Allow|Tcp|10.0.2.0/26|10.20.1.10/32|22",
      "deny-platform-dns|200|Outbound|Deny|*|*|AzurePlatformDNS|*",
      "deny-other-inbound|4000|Inbound|Deny|*|*|*|*",
      "deny-other-outbound|4000|Outbound|Deny|*|*|*|*"
    ])
    error_message = "Backend NSG must allow firewall-subnet source HTTP and Bastion SSH only, with no new outbound Allow."
  }
  assert {
    condition = (
      azurerm_subnet.backend.default_outbound_access_enabled == false &&
      azurerm_network_interface.backend.ip_configuration[0].private_ip_address == "10.20.1.10" &&
      azurerm_network_interface.backend.ip_configuration[0].public_ip_address_id == null &&
      azurerm_virtual_network_peering.hub_to_db.allow_forwarded_traffic &&
      azurerm_virtual_network_peering.db_to_hub.allow_forwarded_traffic &&
      !azurerm_virtual_network_peering.hub_to_db.allow_gateway_transit &&
      !azurerm_virtual_network_peering.db_to_hub.use_remote_gateways
    )
    error_message = "Require the private fixed backend, no NIC public IP and explicit forwarded peering without gateway transit."
  }
}

run "published_exact_dnat_contract" {
  command = plan
  variables { publish_dnat = true }
  assert {
    condition = (
      length(azurerm_firewall_policy_rule_collection_group.dnat) == 1 &&
      azurerm_firewall_policy_rule_collection_group.dnat[0].name == "test-rules" &&
      azurerm_firewall_policy_rule_collection_group.dnat[0].priority == 200 &&
      length(azurerm_firewall_policy_rule_collection_group.dnat[0].network_rule_collection) == 0 &&
      length(azurerm_firewall_policy_rule_collection_group.dnat[0].application_rule_collection) == 0
    )
    error_message = "Publication must create only the intended DNAT group with no unrelated network/application allowances."
  }
  assert {
    condition = toset(flatten([
      for c in azurerm_firewall_policy_rule_collection_group.dnat[0].nat_rule_collection : [
        for r in c.rule : "${c.name}|${c.priority}|${c.action}|${r.name}|${join(",", sort(tolist(r.protocols)))}|${join(",", sort(tolist(r.source_addresses)))}|${join(",", sort(tolist(r.destination_ports)))}|${r.translated_address}|${r.translated_port}"
      ]
    ])) == toset(["publish-test|100|Dnat|operator-only|TCP|9.9.9.9/32|8443|10.20.1.10|8080"])
    error_message = "Exact single-source plain-HTTP port translation contract must remain intact. Destination P wiring is also checked in source-contract tests."
  }
}

run "default_route_removed_completely" {
  command = plan
  variables { enable_default_route = false }
  assert {
    condition     = length(local.route_specs) == 0 && length(azurerm_route.backend) == 0
    error_message = "Removal contrast must delete the standalone default route, not merely omit inline configuration."
  }
}

run "return_blackhole_exact_subnet" {
  command = plan
  variables { return_route_blackhole = true }
  assert {
    condition = (
      toset([for name, r in local.route_specs : "${name}|${r.prefix}|${r.type}"]) == toset([
        "default|0.0.0.0/0|VirtualAppliance", "experiment-return-blackhole|10.0.1.0/26|None"
      ]) &&
      azurerm_route.backend["experiment-return-blackhole"].next_hop_in_ip_address == null
    )
    error_message = "Blackhole must target the firewall /26, not the public client, frontend /32, or Bastion range."
  }
}

run "reject_broad_client" {
  command = plan
  variables { allowed_client_cidr = "9.9.9.0/24" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_documentation_client" {
  command = plan
  variables { allowed_client_cidr = "198.51.100.25/32" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_private_client" {
  command = plan
  variables { allowed_client_cidr = "10.20.1.10/32" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_shared_nat_client" {
  command = plan
  variables { allowed_client_cidr = "100.64.0.1/32" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_multicast_client" {
  command = plan
  variables { allowed_client_cidr = "224.0.0.1/32" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_ipv6_client" {
  command = plan
  variables { allowed_client_cidr = "2001:4860:4860::8888/128" }
  expect_failures = [var.allowed_client_cidr]
}
run "reject_unpinned_image" {
  command = plan
  variables { image_version = "latest" }
  expect_failures = [var.image_version]
}
