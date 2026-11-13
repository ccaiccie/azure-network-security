output "deployment_enabled" { value = var.deploy_lab }
output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "gateway_id" {
  value = try(module.lab[0].gateway_id, null)
}
output "gateway_name" {
  value = try(module.lab[0].gateway_name, null)
}
output "gateway_public_ip" {
  value = try(module.lab[0].gateway_public_ip, null)
}
output "gateway_public_ip_id" {
  value = try(module.lab[0].gateway_public_ip_id, null)
}
output "gateway_subnet_id" {
  value = try(module.lab[0].gateway_subnet_id, null)
}
output "gateway_nsg_id" {
  value = try(module.lab[0].gateway_nsg_id, null)
}
output "gateway_waf_policy_id" {
  value = try(module.lab[0].gateway_waf_policy_id, null)
}
output "edge_waf_policy_id" {
  value = try(module.lab[0].edge_waf_policy_id, null)
}
output "frontdoor_profile_id" {
  value = try(module.lab[0].frontdoor_profile_id, null)
}
output "frontdoor_id" {
  value = try(module.lab[0].frontdoor_id, null)
}
output "edge_endpoint_id" {
  value = try(module.lab[0].edge_endpoint_id, null)
}
output "edge_fqdn" {
  value = try(module.lab[0].edge_fqdn, null)
}
output "edge_route_id" {
  value = try(module.lab[0].edge_route_id, null)
}
output "origin_group_id" {
  value = try(module.lab[0].origin_group_id, null)
}
output "origin_id" {
  value = try(module.lab[0].origin_id, null)
}
output "security_policy_id" {
  value = try(module.lab[0].security_policy_id, null)
}
output "backend_id" {
  value = try(module.lab[0].backend_id, null)
}
output "backend_name" {
  value = try(module.lab[0].backend_name, null)
}
output "backend_fqdn" {
  value = try(module.lab[0].backend_fqdn, null)
}
output "workspace_id" {
  value = try(module.lab[0].workspace_id, null)
}
output "workspace_customer_id" {
  value = try(module.lab[0].workspace_customer_id, null)
}
output "origin_fqdn" {
  value = try(module.lab[0].origin_fqdn, null)
}
output "operator_cidr" {
  value = try(module.lab[0].operator_cidr, null)
}
output "publication_enabled" {
  value = try(module.lab[0].publication_enabled, null)
}
output "gateway_identity_id" {
  value = try(module.lab[0].gateway_identity_id, null)
}
output "gate_state" {
  value = try(module.lab[0].gate_state, null)
}
