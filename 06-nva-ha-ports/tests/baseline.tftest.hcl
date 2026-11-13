# Plan-only mocked provider checks. Supplied NOT RUN; no real Azure or apply.
mock_provider "azurerm" {}
variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "westeurope" # Mock input, NOT a capacity recommendation.
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/nva/versions/1.0.0"
}
run "root_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty root must create nothing."
  }
}
run "deployment_needs_image_attestation" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "exact_ha_topology" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = azurerm_lb.lab.sku == "Standard" && azurerm_lb.lab.sku_tier == "Regional" && length(azurerm_lb.lab.frontend_ip_configuration) == 1 && one(azurerm_lb.lab.frontend_ip_configuration).private_ip_address == "10.0.2.10" && azurerm_lb_backend_address_pool.nvas.name == "nva-pool" && length(azurerm_network_interface_backend_address_pool_association.nvas) == 2
    error_message = "One Standard internal frontend and one two-NIC pool required."
  }
  assert {
    condition     = azurerm_lb_rule.ha.protocol == "All" && azurerm_lb_rule.ha.frontend_port == 0 && azurerm_lb_rule.ha.backend_port == 0 && azurerm_lb_rule.ha.floating_ip_enabled && azurerm_lb_rule.ha.load_distribution == "Default" && azurerm_lb_rule.ha.disable_outbound_snat && !azurerm_lb_rule.ha.tcp_reset_enabled
    error_message = "HA ports must keep the exact All/0/0/Floating IP/five-tuple contract."
  }
  assert {
    condition     = azurerm_lb_probe.readiness.protocol == "Http" && azurerm_lb_probe.readiness.port == 8008 && azurerm_lb_probe.readiness.request_path == "/healthz" && azurerm_lb_probe.readiness.interval_in_seconds == 5 && azurerm_lb_probe.readiness.probe_threshold == 2 && azurerm_lb_probe.readiness.number_of_probes == 2 && azurerm_lb_probe.readiness.no_healthy_backends_behavior == "AllProbedDown"
    error_message = "Readiness and explicit all-unhealthy fail-closed settings required."
  }
  assert {
    condition     = toset(keys(azurerm_network_interface.vm)) == toset(["app", "backend", "nva1", "nva2"]) && alltrue([for name, nic in azurerm_network_interface.vm : nic.ip_forwarding_enabled == contains(["nva1", "nva2"], name)]) && azurerm_bastion_host.lab.sku == "Standard" && azurerm_bastion_host.lab.tunneling_enabled
    error_message = "Only two NVA NICs forward; all four VMs use private Bastion management."
  }
  assert {
    condition     = local.spokes.app.remote == "10.20.0.0/16" && local.spokes.backend.remote == "10.10.0.0/16" && alltrue(flatten([for r in azurerm_route_table.spoke : [for route in r.route : (route.name == "remote-spoke" && route.next_hop_type == "VirtualAppliance" && route.next_hop_in_ip_address == "10.0.2.10") || (route.name == "block-internet" && route.address_prefix == "0.0.0.0/0" && route.next_hop_type == "None")]])) && alltrue([for r in azurerm_route_table.spoke : length(r.route) == 2])
    error_message = "Both spokes must steer the opposite prefix through the same F, with Internet blocked."
  }
  assert {
    condition     = length(azurerm_route_table.nva.route) == 1 && one(azurerm_route_table.nva.route).address_prefix == "0.0.0.0/0" && one(azurerm_route_table.nva.route).next_hop_type == "None" && !azurerm_subnet.nva.default_outbound_access_enabled && alltrue([for s in azurerm_subnet.spoke : !s.default_outbound_access_enabled])
    error_message = "NVA must not point remote prefixes back at F; private subnets have no default outbound."
  }
  assert {
    condition     = local.transit_forward.source == "10.10.1.10/32" && local.transit_forward.destination == "10.20.1.20/32" && toset(local.transit_forward.destination_ports) == toset(["8080", "8081"]) && local.transit_reply.source == "10.20.1.20/32" && local.transit_reply.destination == "10.10.1.10/32" && toset(local.transit_reply.source_ports) == toset(["8080", "8081"]) && alltrue([for name in ["nva1", "nva2"] : length(local.service_rules[name]) == 4])
    error_message = "NSGs must permit original transit tuples including the controlled negative, not NVA-addressed substitutes."
  }
  assert {
    condition     = alltrue([for vm in azurerm_linux_virtual_machine.vm : vm.source_image_id == var.image_id && vm.disable_password_authentication]) && var.nva_zones == null
    error_message = "All VMs use the exact approved image and SSH public key; unzoned default makes no AZ guarantee."
  }
}
run "approved_zone_pair" {
  command = plan
  module { source = "./module" }
  variables {
    nva_zones                     = ["1", "2"]
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = azurerm_linux_virtual_machine.vm["nva1"].zone == "1" && azurerm_linux_virtual_machine.vm["nva2"].zone == "2" && toset(one(azurerm_lb.lab.frontend_ip_configuration).zones) == toset(["1", "2", "3"])
    error_message = "Optional distinct zones must pair with explicitly zone-redundant frontend request."
  }
}
run "reject_same_zone" {
  command = plan
  variables { nva_zones = ["1", "1"] }
  expect_failures = [var.nva_zones]
}
run "reject_single_zone" {
  command = plan
  variables { nva_zones = ["1"] }
  expect_failures = [var.nva_zones]
}
run "reject_bad_zone" {
  command = plan
  variables { nva_zones = ["1", "4"] }
  expect_failures = [var.nva_zones]
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/nva/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_foreign_subscription_image" {
  command = plan
  variables { image_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/nva/versions/1.0.0" }
  expect_failures = [var.image_id]
}
run "reject_private_ssh_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
