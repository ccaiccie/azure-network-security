# Plan-only mocked provider checks, supplied NOT RUN. No Azure/API/apply step.
mock_provider "azurerm" {}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock input, not a capacity recommendation.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_version   = "24.04.202610010"
}
run "root_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && output.deployment_enabled == false
    error_message = "Empty root must create no lab by default."
  }
}
run "closed_infrastructure" {
  command = plan
  module { source = "./module" }
  variables { deploy_lab = true }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.application) == 0 && length(azurerm_firewall_policy_rule_collection_group.negative) == 0 && length(azurerm_firewall_policy_rule_collection_group.override) == 0
    error_message = "All user test groups absent in closed mode."
  }
  assert {
    condition     = azurerm_firewall.lab.sku_tier == "Standard" && azurerm_firewall_policy.lab.sku == "Standard" && azurerm_firewall_policy.lab.threat_intelligence_mode == "Alert"
    error_message = "Standard policy/firewall and Alert TI required."
  }
  assert {
    condition     = jsonencode(local.route_specs.app) == jsonencode([{ name = "default", prefix = "0.0.0.0/0", type = "VirtualAppliance" }, { name = "remote-spoke", prefix = "10.20.0.0/16", type = "VirtualAppliance" }]) && jsonencode(local.route_specs.backend) == jsonencode([{ name = "default", prefix = "0.0.0.0/0", type = "VirtualAppliance" }, { name = "remote-spoke", prefix = "10.10.0.0/16", type = "VirtualAppliance" }])
    error_message = "Both exact private prefixes and defaults must use the appliance; F reference source-checked."
  }
  assert {
    condition     = local.test_nsg_rules.app[0].source == "10.10.1.10/32" && local.test_nsg_rules.app[0].destination == "10.20.1.10/32" && toset(local.test_nsg_rules.app[0].ports) == toset(["8080", "8081"])
    error_message = "App service NSG must admit the exact test envelope including negative8081."
  }
  assert {
    condition     = local.test_nsg_rules.backend[0].source == "10.10.1.10/32" && local.test_nsg_rules.backend[0].priority == 100 && local.test_nsg_rules.backend[1].source == "10.0.1.0/26" && local.test_nsg_rules.backend[1].priority == 101 && alltrue([for r in local.test_nsg_rules.backend : r.destination == "10.20.1.10/32" && toset(r.ports) == toset(["8080", "8081"])])
    error_message = "Backend must permit both network-preserved A and private proxy I sources."
  }
  assert {
    condition     = azurerm_private_dns_zone.lab.name == "policy.test" && !azurerm_private_dns_zone_virtual_network_link.hub.registration_enabled && toset(keys(azurerm_private_dns_a_record.origin)) == toset(["allowed", "denied"]) && alltrue([for r in azurerm_private_dns_a_record.origin : toset(r.records) == toset(["10.20.1.10"]) && r.ttl == 30])
    error_message = "Two manual private DNS names must resolve to one B."
  }
  assert {
    condition     = alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled]) && azurerm_bastion_host.lab.sku == "Standard" && azurerm_bastion_host.lab.tunneling_enabled
    error_message = "Private subnets and Bastion native management required."
  }
}
run "readiness_alone_stays_closed" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab     = true
    fixtures_ready = true
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.application) == 0 && length(azurerm_firewall_policy_rule_collection_group.negative) == 0 && length(azurerm_firewall_policy_rule_collection_group.override) == 0
    error_message = "Readiness must not open a closed policy."
  }
}
run "application_baseline" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab     = true
    fixtures_ready = true
    policy_mode    = "application"
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.override) == 0 && one(azurerm_firewall_policy_rule_collection_group.application).priority == 200
    error_message = "Application baseline must have no8080 network override."
  }
  assert {
    condition     = alltrue([for c in one(azurerm_firewall_policy_rule_collection_group.application).application_rule_collection : (c.name == "deny-test-host" && c.action == "Deny" && c.priority == 100 && one(c.rule).name == "deny-denied-host" && toset(one(c.rule).destination_fqdns) == toset(["denied.policy.test"])) || (c.name == "allow-test-host" && c.action == "Allow" && c.priority == 200 && one(c.rule).name == "allow-approved-host" && toset(one(c.rule).destination_fqdns) == toset(["allowed.policy.test"]))]) && length(one(azurerm_firewall_policy_rule_collection_group.application).application_rule_collection) == 2
    error_message = "Exact application allow/deny hostname contracts required."
  }
  assert {
    condition     = alltrue(flatten([for c in one(azurerm_firewall_policy_rule_collection_group.application).application_rule_collection : [for r in c.rule : toset(r.source_addresses) == toset(["10.10.1.10/32"]) && alltrue([for p in r.protocols : p.type == "Http" && p.port == 8080])]]))
    error_message = "Only A/32 HTTP8080 is tested."
  }
  assert {
    condition     = one(azurerm_firewall_policy_rule_collection_group.negative).priority == 300 && one(one(azurerm_firewall_policy_rule_collection_group.negative).network_rule_collection).action == "Deny" && one(one(one(azurerm_firewall_policy_rule_collection_group.negative).network_rule_collection).rule).name == "deny-app-alternate-port" && toset(one(one(one(azurerm_firewall_policy_rule_collection_group.negative).network_rule_collection).rule).destination_ports) == toset(["8081"])
    error_message = "Named8081 negative must be scoped away from8080."
  }
}
run "network_allow_override" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab            = true
    fixtures_ready        = true
    policy_mode           = "network-allow"
    experiments_confirmed = true
  }
  assert {
    condition     = one(azurerm_firewall_policy_rule_collection_group.override).priority == 65000 && one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).name == "allow-exact-backend" && one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).priority == 65000 && one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).action == "Allow"
    error_message = "Network Allow deliberately uses lower numeric precedence than app groups."
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.application) == 1 && one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).name == "allow-app-backend" && toset(one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).source_addresses) == toset(["10.10.1.10/32"]) && toset(one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).destination_addresses) == toset(["10.20.1.10/32"]) && toset(one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).destination_ports) == toset(["8080"]) && toset(one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).protocols) == toset(["TCP"])
    error_message = "Keep application restrictions while adding only exact A→B TCP8080 Allow."
  }
}
run "network_deny_override" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab            = true
    fixtures_ready        = true
    policy_mode           = "network-deny"
    experiments_confirmed = true
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.application) == 1 && one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).action == "Deny" && one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).name == "deny-exact-backend" && one(one(one(azurerm_firewall_policy_rule_collection_group.override).network_rule_collection).rule).name == "deny-app-backend"
    error_message = "Exactly one Deny override replaces Allow; app controls stay configured."
  }
}
run "application_restored" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab            = true
    fixtures_ready        = true
    policy_mode           = "application"
    experiments_confirmed = false
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.override) == 0 && length(azurerm_firewall_policy_rule_collection_group.application) == 1 && length(azurerm_firewall_policy_rule_collection_group.negative) == 1
    error_message = "Restored application mode must remove network override without dropping the application/negative groups."
  }
}
run "reject_bad_mode" {
  command = plan
  variables { policy_mode = "application-restored" }
  expect_failures = [var.policy_mode]
}
run "reject_unready_application" {
  command = plan
  variables { policy_mode = "application" }
  expect_failures = [var.policy_mode]
}
run "reject_unapproved_override" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab     = true
    fixtures_ready = true
    policy_mode    = "network-allow"
  }
  expect_failures = [var.policy_mode]
}
run "reject_latest_image" {
  command = plan
  variables { image_version = "latest" }
  expect_failures = [var.image_version]
}
