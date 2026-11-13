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
  default     = "inspection-partner"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Standard Virtual WAN/integrated partner NVA, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current Virtual WAN/NVA, VM and Bastion capacity."
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
variable "deploy_lab" {
  type        = bool
  default     = false
  nullable    = false
  description = "New Azure-owned fixtures only. False after deployment is destructive, not a pause."
  validation {
    condition     = !var.deploy_lab || var.image_prerequisites_confirmed
    error_message = "Deployment requires approved exact image prerequisites attestation."
  }
}
variable "image_prerequisites_confirmed" {
  type        = bool
  default     = false
  nullable    = false
  description = "Operator attestation of existing image tools; does not install anything."
}
variable "vendor_ready" {
  type        = bool
  default     = false
  nullable    = false
  description = "External compatible security/dual-role NVA installed/licensed in this hub, with supported manager, routes/SNAT and safe profile reviewed. Not automated proof."
  validation {
    condition     = !var.vendor_ready || (var.deploy_lab && var.vendor_profile != null)
    error_message = "Vendor-ready requires deployed owned infrastructure and a complete nonsecret vendor profile."
  }
}
variable "enable_internet_intent" {
  type        = bool
  default     = false
  nullable    = false
  description = "Attach Internet-only intent to the explicitly existing compatible external NVA. False removes reference, not rollback of prior routing."
  validation {
    condition     = !var.enable_internet_intent || (var.deploy_lab && var.vendor_ready && var.vendor_profile != null)
    error_message = "Intent requires actual externally installed/licensed vendor NVA and reviewed profile."
  }
}
variable "fixtures_ready" {
  type        = bool
  default     = false
  nullable    = false
  description = "Actual local origin8080/8081 health reviewed; not a provisioning-status synonym."
}
variable "internet_routes_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "Actual NIC default, hub defaultRouteTable, vendor direct egress and reverse routes reviewed."
}
variable "vendor_deny_policy_verified" {
  type        = bool
  default     = false
  nullable    = false
  description = "Initial exact named8080/8081 Deny policies installed with logs and no competing broad Allow. Historical baseline attestation, not continuous current vendor action."
}
variable "test_paths_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Allow exact source/origin NSG test envelopes only after all readiness evidence; does not install vendor Allow."
  validation {
    condition     = !var.test_paths_enabled || (var.deploy_lab && var.enable_internet_intent && var.vendor_ready && var.fixtures_ready && var.internet_routes_verified && var.vendor_deny_policy_verified && length(var.egress_public_ips) > 0)
    error_message = "Opening NSGs requires deployed intent, vendor/fixture/route/initial-Deny evidence and complete public egress pool."
  }
}
variable "egress_public_ips" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "Complete observed vendor public SNAT pool, bare global unicast IPv4 addresses only; no secret/vendor config. Never infer it from a documentation example."
  validation {
    condition = length(var.egress_public_ips) <= 16 && alltrue([for ip in var.egress_public_ips : try(
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && cidrhost("${ip}/32", 0) == ip &&
    alltrue([for prefix in ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"] : cidrhost("${ip}/${split("/", prefix)[1]}", 0) != cidrhost(prefix, 0)]), false)])
    error_message = "Supply at most16 bare routable IPv4 egress addresses, excluding private/shared/docs/multicast/reserved/relay ranges."
  }
}
variable "vendor_profile" {
  type = object({
    nva_resource_id           = string
    hub_resource_id           = string
    managed_application_id    = string
    managed_resource_group_id = string
    nva_vendor                = string
    marketplace_publisher     = string
    marketplace_offer         = string
    marketplace_plan          = string
    marketplace_version       = string
    software_version          = string
    scale_unit                = string
    management_system_version = string
    integration_kind          = string
    compatibility_reference   = string
    policy_package_id         = string
    primary_rule_id           = string
    alternate_deny_rule_id    = string
    evidence_reference        = string
  })
  default     = null
  description = "NONSECRET identity/ownership and intended policy contract. No licenses, tokens, credentials, bootstrap URLs or managed-app parameter/outputs. Actual policy installation remains external."
  validation {
    condition = var.vendor_profile == null ? true : try(
      alltrue([for value in values(var.vendor_profile) : length(trimspace(value)) > 0 && length(value) <= 512 && !can(regex("[\\r\\n]", value))]) &&
      contains(["security", "dual_role"], var.vendor_profile.integration_kind) &&
      can(regex("^https://[^ ?#]+$", var.vendor_profile.compatibility_reference)) &&
      can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Network/networkVirtualAppliances/[^/]+$", var.vendor_profile.nva_resource_id)) &&
      can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Solutions/applications/[^/]+$", var.vendor_profile.managed_application_id)) &&
      can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$", var.vendor_profile.managed_resource_group_id)) &&
      alltrue([for id in [var.vendor_profile.nva_resource_id, var.vendor_profile.managed_application_id, var.vendor_profile.managed_resource_group_id] : lower(split("/", id)[2]) == lower(var.subscription_id)]) &&
      lower(var.vendor_profile.hub_resource_id) == lower("/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/virtualHubs/partner-hub") &&
    lower(join("/", slice(split("/", var.vendor_profile.nva_resource_id), 0, 5))) == lower(var.vendor_profile.managed_resource_group_id), false)
    error_message = "Use a complete nonsecret security/dual-role profile: real same-subscription integrated-NVA/managed-app IDs, NVA inside declared managed RG, and this lab partner-hub. Azure Firewall/VM/SaaS IDs are not substitutes."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Nonsecret ownership/cost tags."
}
