variable "subscription_id" {
  description = "Explicit approved Azure public-cloud subscription ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "resource_group_name" {
  description = "NEW dedicated resource group; do not import shared atlas resources."
  type        = string
  default     = "inspection-spp"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Standard Virtual WAN/Zscaler SPP/VPN gateway, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current Virtual WAN/SPP, VM and Bastion capacity."
  }
}

variable "admin_username" {
  description = "Local SSH user; authenticate with an existing approved key."
  type        = string
  default     = "labadmin"
  nullable    = false
  validation {
    condition = (
      can(regex("^[a-z][a-z0-9_-]{0,30}$", var.admin_username)) &&
      !contains(["root", "admin", "administrator", "user", "test", "guest"], var.admin_username)
    )
    error_message = "Choose a nonreserved lowercase Linux username; labadmin is the default."
  }
}

variable "ssh_public_key" {
  description = "Existing PUBLIC OpenSSH key only. Never supply a private key or create one in Terraform."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519) [A-Za-z0-9+/]+={0,3}( [^\\r\\n]+)?$", trimspace(var.ssh_public_key)))
    error_message = "Supply a one-line RSA or Ed25519 public key."
  }
}

variable "vm_size" {
  description = "Available x64 VM size supporting the chosen Ubuntu image; check quota, region and pricing."
  type        = string
  default     = "Standard_B1s"
  nullable    = false
  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.vm_size))
    error_message = "Supply an Azure Standard VM SKU."
  }
}

variable "image_id" {
  description = "REQUIRED approved existing Compute Gallery IMAGE VERSION ID in this subscription. Image must already contain Python3, curl, iproute2, systemd/cloud-init/SSH. No image building or package install is included."
  type        = string
  nullable    = false
  validation {
    condition     = try(can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Compute/galleries/[^/]+/images/[^/]+/versions/[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_id)) && lower(split("/", var.image_id)[2]) == lower(var.subscription_id), false)
    error_message = "Use a concrete approved same-subscription Compute Gallery image version ARM ID, not latest."
  }
}
variable "egress_public_ips" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "Complete observed provider public egress pool, bare global unicast IPv4 addresses only; no secret/vendor config. Never infer it from a documentation example."
  validation {
    condition = length(var.egress_public_ips) <= 16 && alltrue([for ip in var.egress_public_ips : try(
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && cidrhost("${ip}/32", 0) == ip &&
    alltrue([for prefix in ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"] : cidrhost("${ip}/${split("/", prefix)[1]}", 0) != cidrhost(prefix, 0)]), false)])
    error_message = "Supply at most16 bare routable IPv4 egress addresses, excluding private/shared/docs/multicast/reserved/relay ranges."
  }
}
variable "vpn_scale_unit" {
  type        = number
  default     = 1
  nullable    = false
  description = "Approved supported hub VPN gateway capacity. Review service limits, region and cost."
  validation {
    condition     = var.vpn_scale_unit >= 1 && var.vpn_scale_unit <= 10 && floor(var.vpn_scale_unit) == var.vpn_scale_unit
    error_message = "Use a reviewed integer scale unit from1 to10."
  }
}
variable "deploy_lab" {
  type        = bool
  default     = false
  nullable    = false
  description = "Own Azure fixtures/gateway; false after deployment is destruction, not pause."
  validation {
    condition     = !var.deploy_lab || var.image_prerequisites_confirmed
    error_message = "Deployment requires explicit approved exact-image prerequisites."
  }
}
variable "image_prerequisites_confirmed" {
  type        = bool
  default     = false
  nullable    = false
  description = "Approved existing image readiness attestation, not installation or permission."
}
variable "enable_spp" {
  type        = bool
  default     = false
  nullable    = false
  description = "Create the Azure ZScaler association AFTER gateway, not tenant onboarding/tunnels/policy."
  validation {
    condition     = !var.enable_spp || (var.deploy_lab && var.provider_profile != null)
    error_message = "SPP association requires owned infrastructure and selected nonsecret approved provider profile."
  }
}
variable "provider_onboarding_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "External approved ZIA account/license/Azure authorization and location onboarding verified; no credentials are accepted."
}
variable "tunnels_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "Actual required VPN/IPsec links connected on Azure and ZIA sides. Not SPP provisioning status."
}
variable "provider_routing_configured" {
  type        = bool
  default     = false
  nullable    = false
  description = "External owner has configured protected hub SPP routing through the supported workflow. This module does not invent its API."
}
variable "enable_source_default" {
  type        = bool
  default     = false
  nullable    = false
  description = "Terraform-owned app connection Internet-security/default opt-in. Not sufficient to configure protected hub routing."
  validation {
    condition     = !var.enable_source_default || (var.deploy_lab && var.enable_spp && var.provider_onboarding_verified && var.tunnels_verified && var.provider_routing_configured)
    error_message = "Source opt-in requires external onboarding, both-side tunnels and supported hub routing first."
  }
}
variable "protected_routes_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "Actual source chosen default, current hub associations/routes and provider path verified."
}
variable "fixtures_ready" {
  type        = bool
  default     = false
  nullable    = false
  description = "Actual origin1 and origin2 local HTTP80 health reviewed independently."
}
variable "provider_block_policy_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "Initial activated location/client-scoped D1/D2 Block categories/rules and logs reviewed. Historical baseline, not current action."
}
variable "test_paths_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Open only exact app/origin TCP80 NSG envelopes after readiness; does not activate ZIA Allow."
  validation {
    condition     = !var.test_paths_enabled || (var.enable_source_default && var.protected_routes_verified && var.fixtures_ready && var.provider_block_policy_verified && length(var.egress_public_ips) > 0)
    error_message = "Test envelopes require protected default, actual routes/fixtures/activated Block baseline and full E pool."
  }
}
variable "provider_profile" {
  type = object({
    provider                       = string
    zia_cloud                      = string
    tenant_reference               = string
    location_reference             = string
    license_reference              = string
    compatibility_reference        = string
    azure_application_id           = string
    azure_principal_object_id      = string
    approved_scope                 = string
    approved_role_reference        = string
    grant_expiry_reference         = string
    routing_owner_reference        = string
    primary_category_reference     = string
    alternate_category_reference   = string
    primary_rule_reference         = string
    alternate_block_rule_reference = string
    policy_activation_reference    = string
    evidence_reference             = string
  })
  default     = null
  description = "NONSECRET selected Zscaler identity/ownership references only. No passwords, API keys, SP secrets, PSKs, tokens, raw grants or vendor config. It does not create access."
  validation {
    condition = var.provider_profile == null ? true : try(
      var.provider_profile.provider == "ZScaler" &&
      alltrue([for value in values(var.provider_profile) : length(trimspace(value)) > 0 && length(value) <= 512 && !can(regex("[\\r\\n]", value))]) &&
      can(regex("^https://[^ ?#]+$", var.provider_profile.compatibility_reference)) &&
      alltrue([for id in [var.provider_profile.azure_application_id, var.provider_profile.azure_principal_object_id] : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))]) &&
    lower(var.provider_profile.approved_scope) == lower("/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"), false)
    error_message = "Use a complete nonsecret ZScaler profile with approved identity UUIDs and this dedicated RG scope; actual grant creation/use requires separate authorization."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Nonsecret ownership/cost tags."
}
