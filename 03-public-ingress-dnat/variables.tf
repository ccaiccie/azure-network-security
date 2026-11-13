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
  default     = "inspection-dnat"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "Approved region with Firewall, Bastion and selected VM capacity; eastus is retained as an example; 4 Nov 2026 Microsoft lists new East US Firewall Standard deployments blocked. Recheck and approve region explicitly."
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

variable "allowed_client_cidr" {
  description = "REQUIRED approved external client's actual public IPv4/32. One host only; never a documentation example, private prefix or wildcard. Source IP is not user authentication."
  type        = string
  nullable    = false
  validation {
    condition = try(
      can(cidrnetmask(var.allowed_client_cidr)) &&
      endswith(var.allowed_client_cidr, "/32") &&
      var.allowed_client_cidr == "${cidrhost(var.allowed_client_cidr, 0)}/32" &&
      tonumber(split(".", var.allowed_client_cidr)[0]) > 0 &&
      tonumber(split(".", var.allowed_client_cidr)[0]) < 224 &&
      !can(regex("^(10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|192\\.0\\.0\\.|192\\.0\\.2\\.|192\\.88\\.99\\.|198\\.(18|19)\\.|198\\.51\\.100\\.|203\\.0\\.113\\.)", var.allowed_client_cidr)),
      false
    )
    error_message = "Supply one canonical approved public IPv4/32; private/shared/reserved/documentation ranges and broad CIDRs are rejected. Verify actual ownership/source separately."
  }
}

variable "publish_dnat" {
  description = "Default false leaves the backend unpublished. True exposes only allowed_client_cidr to plain HTTP public8443 -> backend8080. Review Internet exposure and authorize deployment first."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_default_route" {
  description = "Baseline true: backend /0 -> F for separately initiated egress. False is the optional contrast; DNAT responses still route to instance I through hub peering."
  type        = bool
  default     = true
  nullable    = false
}

variable "return_route_blackhole" {
  description = "Baseline false. True deliberately adds backend 10.0.1.0/26 -> None, breaking return to any firewall instance without targeting Bastion's distinct /26."
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
