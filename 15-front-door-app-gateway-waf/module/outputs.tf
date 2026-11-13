output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "gateway_id" {
  value = azurerm_application_gateway.lab.id
}
output "gateway_name" {
  value = azurerm_application_gateway.lab.name
}
output "gateway_public_ip" {
  value = azurerm_public_ip.gateway.ip_address
}
output "gateway_public_ip_id" {
  value = azurerm_public_ip.gateway.id
}
output "gateway_subnet_id" {
  value = azurerm_subnet.gateway.id
}
output "gateway_nsg_id" {
  value = azurerm_network_security_group.gateway.id
}
output "gateway_waf_policy_id" {
  value = azurerm_web_application_firewall_policy.gateway.id
}
output "edge_waf_policy_id" {
  value = azurerm_cdn_frontdoor_firewall_policy.edge.id
}
output "frontdoor_profile_id" {
  value = azurerm_cdn_frontdoor_profile.lab.id
}
output "frontdoor_id" {
  value = azurerm_cdn_frontdoor_profile.lab.resource_guid
}
output "edge_endpoint_id" {
  value = azurerm_cdn_frontdoor_endpoint.lab.id
}
output "edge_fqdn" {
  value = azurerm_cdn_frontdoor_endpoint.lab.host_name
}
output "edge_route_id" {
  value = azurerm_cdn_frontdoor_route.lab.id
}
output "origin_group_id" {
  value = azurerm_cdn_frontdoor_origin_group.gateway.id
}
output "origin_id" {
  value = azurerm_cdn_frontdoor_origin.gateway.id
}
output "security_policy_id" {
  value = azurerm_cdn_frontdoor_security_policy.edge.id
}
output "backend_id" {
  value = azurerm_linux_web_app.backend.id
}
output "backend_name" {
  value = azurerm_linux_web_app.backend.name
}
output "backend_fqdn" {
  value = azurerm_linux_web_app.backend.default_hostname
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.lab.id
}
output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.lab.workspace_id
}
output "origin_fqdn" {
  value = var.origin_fqdn
}
output "operator_cidr" {
  value = var.operator_cidr
}
output "publication_enabled" {
  value = var.fixture_publish_enabled
}
output "gateway_identity_id" {
  value = var.gateway_identity_id
}
output "gate_state" {
  value = {
    deploy_lab                      = var.deploy_lab
    certificate_access_confirmed    = var.certificate_access_confirmed
    origin_dns_verified             = var.origin_dns_verified
    fixture_publish_enabled         = var.fixture_publish_enabled
    fixture_ready                   = var.fixture_ready
    backend_access_enabled          = var.backend_access_enabled
    backend_health_verified         = var.backend_health_verified
    gateway_ingress_enabled         = var.gateway_ingress_enabled
    fdid_diagnostic_ingress_enabled = var.fdid_diagnostic_ingress_enabled
    diagnostic_ingress_authorized   = var.diagnostic_ingress_authorized
    fdid_negative_cases_verified    = var.fdid_negative_cases_verified
    edge_route_enabled              = var.edge_route_enabled
  }
}
