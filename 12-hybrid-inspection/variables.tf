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
  default     = "inspection-hybrid"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with VpnGw1AZ, Standard Firewall, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current VPN Gateway/Firewall, VM and Bastion capacity."
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
  description = "False creates nothing in empty state. False after deployment plans destruction, not pause."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.deploy_lab || var.image_prerequisites_confirmed
    error_message = "Deployment requires explicit attestation that the approved image contains the documented tools and clean guest policy."
  }
}
variable "image_prerequisites_confirmed" {
  description = "Operator attestation only, not tool verification or permission. No software/image installation is performed."
  type        = bool
  default     = false
  nullable    = false
}
variable "create_connections" {
  description = "False omits both owned Vnet2Vnet connections. True requires an operator-provided PSK through an approved private input channel; plans/state/backups contain it. Disabling later deletes connections, not an isolation guarantee."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.create_connections || var.deploy_lab
    error_message = "Creating connections requires deployment of the disposable lab."
  }
}
variable "vpn_shared_key" {
  description = "Existing operator-provided matching PSK for BOTH connections. Sensitive hides display only; secret remains in Terraform plans/state/backups. Never commit, print, output, generate here or pass in CLI arguments/chat. Null while connections are omitted."
  type        = string
  default     = null
  sensitive   = true
  nullable    = true
  validation {
    condition     = var.create_connections ? can(regex("^[A-Za-z0-9]{32,128}$", var.vpn_shared_key)) : var.vpn_shared_key == null
    error_message = "Leave PSK null while connections are disabled; enabled connections require an operator-supplied 32-128 character alphanumeric PSK. This format guard is not an entropy/security check. Never reuse test/example values."
  }
}
variable "connections_ready" {
  description = "Historical operator attestation that both intended VPN connections were observed Connected. Not route, encryption, inspection or present health proof."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.connections_ready || (var.deploy_lab && var.create_connections)
    error_message = "Connection readiness cannot be declared without both owned connections enabled."
  }
}
variable "fixtures_ready" {
  description = "Operator attestation of actual local healthy spoke B8080/B8081 and branch A8082 fixtures; not automated proof."
  type        = bool
  default     = false
  nullable    = false
}
variable "private_routes_verified" {
  description = "Operator attestation of actual A-to-B propagated route, gateway steering, B return and firewall onward routes. Not provisioning success."
  type        = bool
  default     = false
  nullable    = false
}
variable "test_paths_enabled" {
  description = "Exact workload NSG test envelope Allow only after readiness review. False isolates new test connections; existing NSG flow state needs separate closure verification."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.test_paths_enabled || (var.deploy_lab && var.fixtures_ready && var.private_routes_verified && var.connections_ready)
    error_message = "Enable NSG test paths only after deployment plus actual fixture and private-route evidence."
  }
}
variable "allow_test_flow" {
  description = "Stable firewall test-flow action: Deny by default, Allow only for explicit reviewed branch A-to-spoke B8080 demo."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.allow_test_flow || (var.deploy_lab && var.test_paths_enabled && var.fixtures_ready && var.private_routes_verified && var.connections_ready)
    error_message = "Allow requires deployment, enabled exact NSG envelope and both readiness attestations."
  }
}
variable "tags" {
  description = "Nonsecret ownership and cost tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
