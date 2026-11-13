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
  default     = "inspection-east-west"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "Approved region with Firewall, Bastion and selected VM capacity; eastus is an example, not verified capacity."
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

variable "explicit_remote_routes" {
  description = "Baseline true: add each remote spoke /16 via F. False is a separate authorized default-route-only experiment; it may still work."
  type        = bool
  default     = true
  nullable    = false
}

variable "return_route_blackhole" {
  description = "Baseline false. True deliberately adds 10.10.1.10/32 -> None on db-inspect, breaking return/reverse routing. Authorization required."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Nonsecret ownership/cost tags; purpose/managed_by remain controlled by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "enable_same_vnet" {
  description = "False baseline. True adds C=10.10.2.20 in a second app-VNet subnet plus A/C inspection routes, rules, NSGs and fixtures."
  type        = bool
  default     = false
  nullable    = false
}

variable "same_vnet_return_route_enabled" {
  description = "True baseline when C is enabled. False deliberately removes only C's return /24, exposing the more-specific local-VNet /16 path."
  type        = bool
  default     = true
  nullable    = false
}
