# Optional offline provider-mocked, plan-only tests. Never use a live provider here.
# Route/NSG specifications are known during plan, unlike the computed firewall IP.
mock_provider "azurerm" {}
variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA offline-test-only"
  image_version   = "0.0.0"
}

run "baseline_exact_routes_nsgs_and_policy" {
  command = plan
  assert {
    condition = toset([for r in local.route_specs.app : "${r.name}|${r.prefix}|${r.type}"]) == toset([
      "default|0.0.0.0/0|VirtualAppliance", "remote-spoke|10.20.0.0/16|VirtualAppliance"
    ])
    error_message = "App baseline must contain exactly the default and remote-db /16 inspection routes."
  }
  assert {
    condition = toset([for r in local.route_specs.db : "${r.name}|${r.prefix}|${r.type}"]) == toset([
      "default|0.0.0.0/0|VirtualAppliance", "remote-spoke|10.10.0.0/16|VirtualAppliance"
    ])
    error_message = "Db baseline must contain exactly the default and remote-app /16 inspection routes."
  }
  assert {
    condition = toset([for r in local.test_nsg_rules.app : "${r.direction}|${r.priority}|${r.source}|${r.destination}|${join(",", r.ports)}"]) == toset([
      "Inbound|100|10.20.1.10/32|10.10.1.10/32|8080",
      "Outbound|100|10.10.1.10/32|10.20.1.10/32|8080,8081"
    ])
    error_message = "App NSG test paths must exactly permit positive/negative forward probes and the reverse probe."
  }
  assert {
    condition = toset([for r in local.test_nsg_rules.db : "${r.direction}|${r.priority}|${r.source}|${r.destination}|${join(",", r.ports)}"]) == toset([
      "Inbound|100|10.10.1.10/32|10.20.1.10/32|8080,8081",
      "Outbound|100|10.20.1.10/32|10.10.1.10/32|8080"
    ])
    error_message = "Db NSG must permit the original source on both ports and the reverse-initiation probe."
  }
  assert {
    condition = toset(flatten([
      for c in azurerm_firewall_policy_rule_collection_group.east_west.network_rule_collection : [
        for r in c.rule : "${c.name}|${c.priority}|${c.action}|${r.name}|${join(",", sort(tolist(r.source_addresses)))}|${join(",", sort(tolist(r.destination_addresses)))}|${join(",", sort(tolist(r.destination_ports)))}|${join(",", sort(tolist(r.protocols)))}"
      ]
      ])) == toset([
      "allow-private-fixture|100|Allow|allow-app-to-test|10.10.1.10/32|10.20.1.10/32|8080|TCP",
      "deny-negative-fixtures|200|Deny|deny-reverse-new|10.20.1.10/32|10.10.1.10/32|*|TCP",
      "deny-negative-fixtures|200|Deny|deny-app-alternate-port|10.10.1.10/32|10.20.1.10/32|8081|TCP"
    ])
    error_message = "Baseline firewall collections, priorities, actions, tuples and names must match exactly."
  }
  assert {
    condition = (
      azurerm_subnet.workload["app"].default_outbound_access_enabled == false &&
      azurerm_subnet.workload["db"].default_outbound_access_enabled == false &&
      length(azurerm_virtual_network.workload) == 2 &&
      length(azurerm_linux_virtual_machine.workload) == 2 &&
      !contains(keys(local.workloads), "c")
    )
    error_message = "Baseline has exactly two private workload subnets/VMs and no optional C."
  }
  assert {
    condition = (
      azurerm_virtual_network_peering.hub_to_app.allow_forwarded_traffic &&
      azurerm_virtual_network_peering.app_to_hub.allow_forwarded_traffic &&
      azurerm_virtual_network_peering.hub_to_db.allow_forwarded_traffic &&
      azurerm_virtual_network_peering.db_to_hub.allow_forwarded_traffic &&
      azurerm_firewall_policy_rule_collection_group.east_west.priority == 300 &&
      length(azurerm_firewall_policy_rule_collection_group.east_west.application_rule_collection) == 0
    )
    error_message = "Require four forwarded peerings, group priority 300 and no application rules."
  }
}

run "default_route_only_has_no_remote_16s" {
  command = plan
  variables { explicit_remote_routes = false }
  assert {
    condition = alltrue([for role in ["app", "db"] :
      toset([for r in local.route_specs[role] : "${r.name}|${r.prefix}|${r.type}"]) == toset(["default|0.0.0.0/0|VirtualAppliance"])
    ])
    error_message = "The default-only experiment must remove both /16s and preserve both /0 routes."
  }
}

run "blackhole_only_changes_db_return" {
  command = plan
  variables { return_route_blackhole = true }
  assert {
    condition = (
      toset([for r in local.route_specs.db : "${r.name}|${r.prefix}|${r.type}"]) == toset([
        "default|0.0.0.0/0|VirtualAppliance", "remote-spoke|10.10.0.0/16|VirtualAppliance",
        "experiment-return-blackhole|10.10.1.10/32|None"
      ]) && length(local.route_specs.app) == 2
    )
    error_message = "Only db may receive the exact A/32 None route; app retains its baseline routes."
  }
}

run "same_vnet_exact_resources_routes_and_nsgs" {
  command = plan
  variables { enable_same_vnet = true }
  assert {
    condition = (
      length(azurerm_virtual_network.workload) == 2 &&
      length(azurerm_linux_virtual_machine.workload) == 3 &&
      azurerm_subnet.workload["c"].virtual_network_name == "app" &&
      azurerm_subnet.workload["c"].name == "same-vnet" &&
      toset(azurerm_subnet.workload["c"].address_prefixes) == toset(["10.10.2.0/24"]) &&
      local.workloads.c.private_ip == "10.10.2.20" &&
      toset(local.workloads.c.listen_ports) == toset([8080, 8081])
    )
    error_message = "C must be a third VM in the existing app VNet, separate /24 subnet, fixed private IP and both fixture ports."
  }
  assert {
    condition = (
      toset([for r in local.route_specs.app : "${r.name}|${r.prefix}|${r.type}"]) == toset([
        "default|0.0.0.0/0|VirtualAppliance", "remote-spoke|10.20.0.0/16|VirtualAppliance",
        "same-vnet-forward|10.10.2.0/24|VirtualAppliance"
      ]) &&
      toset([for r in local.route_specs.c : "${r.name}|${r.prefix}|${r.type}"]) == toset([
        "default|0.0.0.0/0|VirtualAppliance", "same-vnet-return|10.10.1.0/24|VirtualAppliance"
      ])
    )
    error_message = "Both dedicated A/C /24 inspection routes are required in the optional baseline."
  }
  assert {
    condition = toset([for r in local.test_nsg_rules.c : "${r.direction}|${r.source}|${r.destination}|${join(",", r.ports)}"]) == toset([
      "Inbound|10.10.1.10/32|10.10.2.20/32|8080,8081",
      "Outbound|10.10.2.20/32|10.10.1.10/32|8080"
    ])
    error_message = "C NSG must permit exactly the intended A/C firewall probes."
  }
  assert {
    condition = toset([for r in local.test_nsg_rules.app : "${r.direction}|${r.priority}|${r.source}|${r.destination}|${join(",", r.ports)}"]) == toset([
      "Inbound|100|10.20.1.10/32|10.10.1.10/32|8080",
      "Outbound|100|10.10.1.10/32|10.20.1.10/32|8080,8081",
      "Inbound|101|10.10.2.20/32|10.10.1.10/32|8080",
      "Outbound|101|10.10.1.10/32|10.10.2.20/32|8080,8081"
    ])
    error_message = "A must add scoped C paths without changing its B test paths."
  }
  assert {
    condition = toset(flatten([
      for c in azurerm_firewall_policy_rule_collection_group.east_west.network_rule_collection : [
        for r in c.rule : "${c.action}|${r.name}|${join(",", sort(tolist(r.source_addresses)))}|${join(",", sort(tolist(r.destination_addresses)))}|${join(",", sort(tolist(r.destination_ports)))}"
        if contains(["allow-app-to-same-vnet", "deny-same-vnet-reverse-new", "deny-same-vnet-alternate-port"], r.name)
      ]
      ])) == toset([
      "Allow|allow-app-to-same-vnet|10.10.1.10/32|10.10.2.20/32|8080",
      "Deny|deny-same-vnet-reverse-new|10.10.2.20/32|10.10.1.10/32|*",
      "Deny|deny-same-vnet-alternate-port|10.10.1.10/32|10.10.2.20/32|8081"
    ])
    error_message = "Optional C firewall rules must preserve the exact narrow tuple and named deny contract."
  }
}

run "same_vnet_asymmetry_removes_only_c_return_24" {
  command = plan
  variables {
    enable_same_vnet               = true
    same_vnet_return_route_enabled = false
  }
  assert {
    condition = (
      toset([for r in local.route_specs.c : "${r.name}|${r.prefix}|${r.type}"]) == toset(["default|0.0.0.0/0|VirtualAppliance"]) &&
      contains([for r in local.route_specs.app : r.prefix], "10.10.2.0/24") &&
      length(local.route_specs.db) == 2
    )
    error_message = "Only C's return /24 is removed; A's forward /24 and B baseline stay intact."
  }
}

run "default_only_does_not_remove_same_vnet_24s" {
  command = plan
  variables {
    enable_same_vnet       = true
    explicit_remote_routes = false
  }
  assert {
    condition = (
      toset([for r in local.route_specs.app : r.prefix]) == toset(["0.0.0.0/0", "10.10.2.0/24"]) &&
      toset([for r in local.route_specs.c : r.prefix]) == toset(["0.0.0.0/0", "10.10.1.0/24"])
    )
    error_message = "The spoke /16 experiment must not silently remove separate same-VNet /24 controls."
  }
}

run "reject_unpinned_image" {
  command = plan
  variables { image_version = "latest" }
  expect_failures = [var.image_version]
}
