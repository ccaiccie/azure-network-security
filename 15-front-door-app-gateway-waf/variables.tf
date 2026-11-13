variable "subscription_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Use the approved subscription UUID."
  }
}
variable "resource_group_name" {
  type     = string
  default  = "inspection-waf"
  nullable = false
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{2,62}$", var.resource_group_name))
    error_message = "Use a new dedicated resource-group name."
  }
}
variable "location" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,30}$", var.location))
    error_message = "Specify an approved Azure public region with all required capacity."
  }
}
variable "backend_name" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,49}[a-z0-9]$", var.backend_name))
    error_message = "Use a new globally unique App Service name."
  }
}
variable "edge_endpoint_name" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,49}[a-z0-9]$", var.edge_endpoint_name))
    error_message = "Use a new globally unique Front Door endpoint name."
  }
}
variable "origin_fqdn" {
  type     = string
  nullable = false
  validation {
    condition     = length(var.origin_fqdn) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.origin_fqdn)) && !endswith(var.origin_fqdn, ".example") && !endswith(var.origin_fqdn, ".invalid") && !endswith(var.origin_fqdn, ".localhost")
    error_message = "Use an approved, lowercase public origin DNS name covered by the existing certificate."
  }
}
variable "operator_cidr" {
  type     = string
  nullable = false
  validation {
    condition     = can(cidrhost(var.operator_cidr, 0)) && endswith(var.operator_cidr, "/32") && !strcontains(var.operator_cidr, ":") && try("${cidrhost(var.operator_cidr, 0)}/32" == var.operator_cidr, false) && try(tonumber(split(".", var.operator_cidr)[0]) >= 1 && tonumber(split(".", var.operator_cidr)[0]) < 224, false) && !can(regex("^(10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|192\\.0\\.[02]\\.|198\\.(1[89]\\.|51\\.100\\.)|203\\.0\\.113\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.)", var.operator_cidr))
    error_message = "Supply the actual approved public unicast IPv4 /32, not private/shared/documentation or reserved space; operator helpers apply stricter public-address checks too."
  }
}
variable "gateway_identity_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/${var.subscription_id}/resourceGroups/[a-z0-9._()-]+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[a-z0-9._()-]+$", var.gateway_identity_id))
    error_message = "Reference an existing same-subscription approved user-assigned identity. No identity or grant is created here."
  }
}
variable "listener_key_vault_secret_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^https://[a-z0-9-]{3,24}\\.vault\\.azure\\.net/secrets/[A-Za-z0-9-]{1,127}$", var.listener_key_vault_secret_id))
    error_message = "Use the versionless public-cloud Key Vault secret URI of an approved existing software certificate; no secret value, query, password or version."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Public non-sensitive labels only. Tags are not automatically redacted."
}
variable "deploy_lab" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.deploy_lab || var.certificate_access_confirmed
    error_message = "Deployment requires prior approval and readiness of the existing certificate, identity, access and network path."
  }
}
variable "certificate_access_confirmed" {
  type     = bool
  default  = false
  nullable = false
}
variable "origin_dns_verified" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.origin_dns_verified || var.deploy_lab
    error_message = "DNS attestation requires the owned deployed public IP."
  }
}
variable "fixture_publish_enabled" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.fixture_publish_enabled || (var.deploy_lab && !var.edge_route_enabled && !var.fdid_diagnostic_ingress_enabled)
    error_message = "SCM publication requires deployed substrate and closed edge/diagnostic paths."
  }
}
variable "fixture_ready" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.fixture_ready || var.deploy_lab
    error_message = "Fixture readiness requires deployment and separate approved publication."
  }
}
variable "backend_access_enabled" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.backend_access_enabled || (var.deploy_lab && var.fixture_ready)
    error_message = "Backend access requires the reviewed deployed fixture."
  }
}
variable "backend_health_verified" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.backend_health_verified || (var.backend_access_enabled && var.fixture_ready)
    error_message = "Backend health attestation requires the open gateway-to-backend path."
  }
}
variable "gateway_ingress_enabled" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.gateway_ingress_enabled || (var.deploy_lab && var.origin_dns_verified && var.backend_health_verified)
    error_message = "Front Door ingress requires DNS, fixture and backend health evidence."
  }
}
variable "fdid_diagnostic_ingress_enabled" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.fdid_diagnostic_ingress_enabled || (var.deploy_lab && var.diagnostic_ingress_authorized && var.origin_dns_verified && var.backend_health_verified && !var.edge_route_enabled && !var.fixture_publish_enabled)
    error_message = "Diagnostic C/32 ingress requires explicit approval, healthy backend and closed edge/publication paths."
  }
}
variable "diagnostic_ingress_authorized" {
  type     = bool
  default  = false
  nullable = false
}
variable "fdid_negative_cases_verified" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.fdid_negative_cases_verified || var.deploy_lab
    error_message = "FDID evidence is a historical attestation, never an automated test result."
  }
}
variable "edge_route_enabled" {
  type     = bool
  default  = false
  nullable = false
  validation {
    condition     = !var.edge_route_enabled || (var.deploy_lab && var.gateway_ingress_enabled && var.backend_health_verified && var.fdid_negative_cases_verified && !var.fdid_diagnostic_ingress_enabled && !var.fixture_publish_enabled)
    error_message = "Edge publication requires verified header cases, DNS/TLS/backend health and closed diagnostic/SCM exceptions."
  }
}
