# Optional offline tests for an operator with Terraform and the pinned provider.
# This mock replaces Azure CRUD. All runs are plan-only and must stay mocked.
mock_provider "azurerm" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  # Structurally encoded all-zero public-key fixture. No private key exists here.
  # NEVER use this fixture for an actual deployment.
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA offline-test-fixture"
}

run "network_policy_is_scoped" {
  command = plan

  variables {
    policy_mode = "network"
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection) == 1
    error_message = "Network mode must contain exactly one network collection."
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection) == 0
    error_message = "Application collection must be absent in network mode."
  }

  assert {
    condition     = azurerm_subnet.workload.default_outbound_access_enabled == false
    error_message = "Workload subnet must be private explicitly."
  }

  assert {
    condition     = azurerm_firewall_policy.egress.dns[0].proxy_enabled == true
    error_message = "Network FQDN filtering requires DNS proxy."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.workload.disable_password_authentication == true
    error_message = "SSH must not allow password authentication."
  }

  assert {
    condition = (
      azurerm_virtual_network_peering.hub_to_spoke.allow_forwarded_traffic &&
      azurerm_virtual_network_peering.spoke_to_hub.allow_forwarded_traffic
    )
    error_message = "Both peering directions must permit forwarded traffic."
  }
}

run "application_policy_replaces_network_policy" {
  command = plan

  variables {
    policy_mode = "application"
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection) == 0
    error_message = "Network collection must be absent so it cannot bypass application filtering."
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection) == 1
    error_message = "Application mode must contain exactly one application collection."
  }
}

run "invalid_mode_is_rejected" {
  command = plan

  variables {
    policy_mode = "allow-everything"
  }

  expect_failures = [var.policy_mode]
}

run "wildcard_fqdn_is_rejected" {
  command = plan

  variables {
    allowed_fqdns = ["*.microsoft.com"]
  }

  expect_failures = [var.allowed_fqdns]
}
