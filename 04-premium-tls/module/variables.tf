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
  default     = "inspection-tls"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "Approved region with Firewall, Bastion and selected VM capacity; eastus is an example; check current Premium, Bastion, VM and App Service capacity, policy and pricing. No region readiness is assumed."
  type        = string
  default     = "eastus"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region identifier, such as eastus."
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

variable "image_version" {
  description = "REQUIRED concrete Canonical ubuntu-24_04-lts:server image version, resolved and approved for the chosen region. No latest default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Resolve and pin a three-component image version. latest is deliberately rejected."
  }
}

variable "operator_cidr" {
  description = "REQUIRED approved operator public IPv4/32 for App Service preflight and SCM code upload only. Never a broad/documentation/private source."
  type        = string
  nullable    = false
  validation {
    condition = try(
      can(cidrnetmask(var.operator_cidr)) &&
      endswith(var.operator_cidr, "/32") &&
      var.operator_cidr == "${cidrhost(var.operator_cidr, 0)}/32" &&
      tonumber(split(".", var.operator_cidr)[0]) > 0 &&
      tonumber(split(".", var.operator_cidr)[0]) < 224 &&
      !can(regex("^(10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|192\\.0\\.0\\.|192\\.0\\.2\\.|192\\.88\\.99\\.|198\\.(18|19)\\.|198\\.51\\.100\\.|203\\.0\\.113\\.)", var.operator_cidr)),
      false
    )
    error_message = "Supply one canonical approved public IPv4/32; private/shared/reserved/documentation ranges and broad CIDRs are rejected. Verify actual ownership/source separately."
  }
}


variable "origin_name" {
  description = "Required globally unique approved App Service app name; actual default_hostname is computed, never guessed."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,58}[a-z0-9]$", var.origin_name))
    error_message = "Use 3-60 lowercase letters, digits and hyphens, starting with a letter and ending alphanumeric."
  }
}
variable "deploy_lab" {
  description = "Safety default false: root module creates no resources. True requires separate reviewed deployment/cost authorization."
  type        = bool
  default     = false
  nullable    = false
}
variable "enable_tls_inspection" {
  description = "False until existing CA, identity access, network retrieval and linkage approval are verified. True configures the preexisting CA/identity on policy."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.enable_tls_inspection || (var.deploy_lab && var.tls_prerequisites_confirmed)
    error_message = "Inspection linkage requires deploy_lab=true and explicit tls_prerequisites_confirmed=true; these flags do not replace security approval."
  }
}
variable "tls_prerequisites_confirmed" {
  description = "Operator attestation only: existing PKI/Key Vault/identity access and explicit policy linkage are approved. Does not create permissions or verify retrieval."
  type        = bool
  default     = false
  nullable    = false
}
variable "origin_fixture_ready" {
  description = "False until the included origin ZIP is separately published and direct /allowed plus /blocked and public certificate validate. True enables application rules only with inspection enabled."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.origin_fixture_ready || var.enable_tls_inspection
    error_message = "Origin-ready application policy requires enable_tls_inspection=true."
  }
}
variable "tls_secret_uri" {
  description = "Existing approved VERSIONED Key Vault secrets URI for intermediate CA PFX. Identifier only; never supply secret value, PFX or private key."
  type        = string
  default     = null
  validation {
    condition     = (var.tls_secret_uri == null && !var.enable_tls_inspection) || can(regex("^https://[a-z0-9-]{3,24}\\.vault\\.azure\\.net/secrets/[A-Za-z0-9-]+/[0-9a-fA-F]{32}$", var.tls_secret_uri))
    error_message = "Inspection requires an approved versioned https://VAULT.vault.azure.net/secrets/NAME/VERSION identifier without query or secret contents."
  }
}
variable "tls_identity_id" {
  description = "Existing preapproved user-assigned managed identity ARM ID in the approved subscription. No identity or role/access-policy grant is created."
  type        = string
  default     = null
  validation {
    condition = (var.tls_identity_id == null && !var.enable_tls_inspection) || try(
      can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[^/]+$", var.tls_identity_id)) &&
    lower(split("/", var.tls_identity_id)[2]) == lower(var.subscription_id), false)
    error_message = "Inspection requires the approved existing user-assigned identity ID in this subscription."
  }
}
variable "tags" {
  description = "Nonsecret ownership and cost tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
