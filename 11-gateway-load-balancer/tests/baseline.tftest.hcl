# PLAN-ONLY mock-provider cases supplied, NOT RUN; never real Azure/apply.
mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = { ip_address = "20.40.1.10" }
  }
}
variables {
  subscription_id  = "11111111-1111-1111-1111-111111111111"
  location         = "westeurope" # Mock-only, not a capacity recommendation.
  ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockOnlyNeverUseForDeployment"
  image_id         = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/gwlb/versions/1.0.0"
  client_public_ip = "20.40.2.10" # Mock only, never contacted.
}
run "root_disabled" {
  command = plan
  assert {
    condition     = length(module.lab) == 0 && !output.deployment_enabled
    error_message = "Default empty-state root must create no resources."
  }
}
run "deployment_needs_image_attestation" {
  command = plan
  variables { deploy_lab = true }
  expect_failures = [var.deploy_lab]
}
run "chain_requires_readiness" {
  command = plan
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    enable_chain                  = true
  }
  expect_failures = [var.enable_chain]
}
run "test_paths_need_chain" {
  command = plan
  variables { test_paths_enabled = true }
  expect_failures = [var.test_paths_enabled]
}
run "exact_closed_topology" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
  }
  assert {
    condition     = azurerm_lb.inspection.sku == "Gateway" && azurerm_lb.inspection.sku_tier == "Regional" && length(azurerm_lb.inspection.frontend_ip_configuration) == 1 && one(azurerm_lb.inspection.frontend_ip_configuration).private_ip_address == "10.0.2.10" && length(azurerm_network_interface_backend_address_pool_association.nvas) == 2
    error_message = "One Gateway frontend and exact two-NIC pool required."
  }
  assert {
    condition     = length(azurerm_lb_backend_address_pool.nvas.tunnel_interface) == 2 && alltrue([for t in azurerm_lb_backend_address_pool.nvas.tunnel_interface : t.protocol == "VXLAN" && ((t.type == "Internal" && t.identifier == 800 && t.port == 10800) || (t.type == "External" && t.identifier == 801 && t.port == 10801))])
    error_message = "Exact VXLAN pair must match the Linux interfaces."
  }
  assert {
    condition     = azurerm_lb_rule.inspection.protocol == "All" && azurerm_lb_rule.inspection.frontend_port == 0 && azurerm_lb_rule.inspection.backend_port == 0 && !azurerm_lb_rule.inspection.floating_ip_enabled && azurerm_lb_rule.inspection.disable_outbound_snat && !azurerm_lb_rule.inspection.tcp_reset_enabled
    error_message = "Gateway All/0/0 must not inherit Standard ILB Floating-IP behavior."
  }
  assert {
    condition     = azurerm_lb.consumer.sku == "Standard" && azurerm_lb.consumer.sku_tier == "Regional" && one(azurerm_lb.consumer.frontend_ip_configuration).gateway_load_balancer_frontend_ip_configuration_id == null && length(azurerm_lb_rule.app) == 2 && alltrue([for k, r in azurerm_lb_rule.app : r.frontend_port == tonumber(k) && r.backend_port == tonumber(k) && !r.floating_ip_enabled && r.disable_outbound_snat])
    error_message = "Bootstrap is unchained and closed, with exact inbound-only comparison ports."
  }
  assert {
    condition     = azurerm_lb_probe.nva.port == 8008 && azurerm_lb_probe.app.port == 8009 && azurerm_lb_probe.nva.request_path == "/health" && azurerm_lb_probe.app.request_path == "/health" && azurerm_lb_probe.nva.no_healthy_backends_behavior == "AllProbedDown" && azurerm_lb_probe.app.no_healthy_backends_behavior == "AllProbedDown" && azurerm_lb_probe.nva.interval_in_seconds == 5 && azurerm_lb_probe.nva.probe_threshold == 2
    error_message = "Independent application and structural NVA probes are required."
  }
  assert {
    condition     = alltrue([for name, nic in azurerm_network_interface.vm : nic.ip_forwarding_enabled == (name != "app") && one(nic.ip_configuration).public_ip_address_id == null]) && alltrue([for s in azurerm_subnet.workload : !s.default_outbound_access_enabled])
    error_message = "Only NVA NICs forward; workloads have no public NIC or default outbound access."
  }
  assert {
    condition     = length(azurerm_virtual_network_peering.management_to_target) == 2 && length(azurerm_virtual_network_peering.target_to_management) == 2 && alltrue([for p in azurerm_virtual_network_peering.management_to_target : !p.allow_forwarded_traffic && !p.allow_gateway_transit && !p.use_remote_gateways]) && azurerm_bastion_host.lab.sku == "Standard" && azurerm_bastion_host.lab.tunneling_enabled
    error_message = "Private management must use only isolated management-to-target peerings."
  }
  assert {
    condition     = local.test_nsg_action == "Deny" && one([for r in azurerm_network_security_group.vm["app"].security_rule : r if r.name == "test-client-ingress"]).source_address_prefix == "20.40.2.10/32" && one([for r in azurerm_network_security_group.vm["app"].security_rule : r if r.name == "test-client-ingress"]).destination_address_prefix == "10.20.1.20/32" && alltrue([for name in ["nva1", "nva2"] : one([for r in azurerm_network_security_group.vm[name].security_rule : r if r.name == "vxlan-inbound"]).source_address_prefix == "10.0.0.0/16"])
    error_message = "Closed exact endpoint NSG plus bounded provider transport envelope required."
  }
}
run "chain_with_closed_test_envelope" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    appliances_ready              = true
    application_ready             = true
    enable_chain                  = true
  }
  assert {
    condition     = one(azurerm_lb.consumer.frontend_ip_configuration).gateway_load_balancer_frontend_ip_configuration_id == one(azurerm_lb.inspection.frontend_ip_configuration).id && local.test_nsg_action == "Deny"
    error_message = "Chain attaches while exact app test ingress stays closed."
  }
}
run "exact_test_envelope_open" {
  command = plan
  module { source = "./module" }
  variables {
    deploy_lab                    = true
    image_prerequisites_confirmed = true
    appliances_ready              = true
    application_ready             = true
    enable_chain                  = true
    test_paths_enabled            = true
  }
  assert {
    condition     = local.test_nsg_action == "Allow" && one([for r in azurerm_network_security_group.vm["app"].security_rule : r if r.name == "test-client-ingress"]).access == "Allow"
    error_message = "Only explicit activation opens exact C-to-B test ingress."
  }
}
run "reject_documentation_client" {
  command = plan
  variables { client_public_ip = "198.51.100.10" }
  expect_failures = [var.client_public_ip]
}
run "reject_private_client" {
  command = plan
  variables { client_public_ip = "10.1.2.3" }
  expect_failures = [var.client_public_ip]
}
run "reject_latest_image" {
  command = plan
  variables { image_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/gwlb/versions/latest" }
  expect_failures = [var.image_id]
}
run "reject_foreign_image" {
  command = plan
  variables { image_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/image-rg/providers/Microsoft.Compute/galleries/approved/images/gwlb/versions/1.0.0" }
  expect_failures = [var.image_id]
}
run "reject_private_key" {
  command = plan
  variables { ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.ssh_public_key]
}
