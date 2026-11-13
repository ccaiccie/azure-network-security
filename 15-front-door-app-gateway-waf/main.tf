module "lab" {
  source                          = "./module"
  count                           = var.deploy_lab ? 1 : 0
  subscription_id                 = var.subscription_id
  resource_group_name             = var.resource_group_name
  location                        = var.location
  backend_name                    = var.backend_name
  edge_endpoint_name              = var.edge_endpoint_name
  origin_fqdn                     = var.origin_fqdn
  operator_cidr                   = var.operator_cidr
  gateway_identity_id             = var.gateway_identity_id
  listener_key_vault_secret_id    = var.listener_key_vault_secret_id
  tags                            = var.tags
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
