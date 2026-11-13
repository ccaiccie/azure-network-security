variable "subscription_id" {
  description = "Explicit Azure public-cloud subscription ID. Authentication uses your authorized Azure CLI session or approved environment credentials."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "resource_group_name" {
  description = "Name of a NEW dedicated lab resource group. Never import a shared resource group into this demo."
  type        = string
  default     = "rg-egress-demo"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, starting and ending with a letter or digit."
  }
}

variable "location" {
  description = "Approved Azure region with Firewall Standard, Bastion Standard, VM SKU capacity and quota. Availability has not been checked."
  type        = string
  default     = "eastus"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region identifier such as eastus, not its display name."
  }
}

variable "admin_username" {
  description = "Local Linux SSH user. There is no password authentication."
  type        = string
  default     = "labadmin"
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9_-]{0,30}$", var.admin_username)) &&
      !contains(["root", "admin", "administrator", "user", "test", "guest", "azureuser"], var.admin_username)
    )
    error_message = "Use a nonreserved lowercase Linux username, at most 31 characters; labadmin is the default."
  }
}

variable "ssh_public_key" {
  description = "Existing approved SSH PUBLIC key only. Keep the private key on your workstation; do not pass it to Terraform."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519) [A-Za-z0-9+/]+={0,3}( [^\\r\\n]+)?$", trimspace(var.ssh_public_key)))
    error_message = "Provide a one-line OpenSSH RSA or Ed25519 public key, never a private key."
  }
}

variable "vm_size" {
  description = "An available x64 VM size in the approved region; check quota and pricing before deployment."
  type        = string
  default     = "Standard_B1s"
  nullable    = false

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.vm_size))
    error_message = "Use a valid Azure Standard VM SKU."
  }
}

variable "image_version" {
  description = "Canonical Ubuntu 24.04 LTS server image version. Resolve and pin a concrete version for reproducible deployment."
  type        = string
  default     = "latest"
  nullable    = false

  validation {
    condition     = var.image_version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Use latest or a concrete three-component marketplace image version."
  }
}

variable "policy_mode" {
  description = "network demonstrates DNS-derived IP allowlisting and network-rule SNAT. application is a separate HTTPS Host/SNI comparison scenario. Collections are mutually exclusive."
  type        = string
  default     = "network"
  nullable    = false

  validation {
    condition     = contains(["network", "application"], var.policy_mode)
    error_message = "policy_mode must be network or application."
  }
}

variable "allowed_fqdns" {
  description = "Exact approved public DNS hostnames. Network mode permits their resolved IPs on TCP/443; it does not enforce HTTP Host/SNI. No wildcards, URLs or IP literals."
  type        = set(string)
  default     = ["www.microsoft.com", "api.ipify.org"]
  nullable    = false

  validation {
    condition = length(var.allowed_fqdns) > 0 && length(var.allowed_fqdns) <= 20 && alltrue([
      for fqdn in var.allowed_fqdns : (
        length(fqdn) <= 253 &&
        fqdn == lower(fqdn) &&
        can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", fqdn))
      )
    ])
    error_message = "Supply 1-20 exact lowercase DNS names, each at most 253 characters, without wildcards, IPs, scheme, path or trailing dot."
  }
}

variable "tags" {
  description = "Nonsecret ownership/cost tags. Built-in purpose and managed_by labels cannot be overwritten."
  type        = map(string)
  default     = {}
  nullable    = false
}
