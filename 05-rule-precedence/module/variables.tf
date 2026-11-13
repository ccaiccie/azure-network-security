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
  default     = "inspection-policy"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Standard Firewall, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current Standard capacity."
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

variable "deploy_lab" {
  description = "False creates nothing in empty state; false after deployment plans destruction, not pause."
  type        = bool
  default     = false
  nullable    = false
}
variable "fixtures_ready" {
  description = "Operator attestation after backend local healthy8080/8081 controls; not a runtime verification by Terraform."
  type        = bool
  default     = false
  nullable    = false
}
variable "policy_mode" {
  description = "closed|application|network-allow|network-deny; restoration selects application again. Nonclosed modes require deployment and fixture readiness."
  type        = string
  default     = "closed"
  nullable    = false
  validation {
    condition     = contains(["closed", "application", "network-allow", "network-deny"], var.policy_mode)
    error_message = "Select exactly one supported policy mode."
  }
  validation {
    condition     = var.policy_mode == "closed" || (var.deploy_lab && var.fixtures_ready)
    error_message = "Nonclosed modes require deploy_lab=true and fixtures_ready=true after actual local controls."
  }
  validation {
    condition     = !contains(["network-allow", "network-deny"], var.policy_mode) || var.experiments_confirmed
    error_message = "Network override modes require explicit experiments_confirmed=true after review/authorization."
  }
}
variable "experiments_confirmed" {
  description = "Operator attestation for this dedicated lab's reviewed exact network override; never grants permission itself."
  type        = bool
  default     = false
  nullable    = false
}
variable "tags" {
  description = "Nonsecret ownership and cost tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
