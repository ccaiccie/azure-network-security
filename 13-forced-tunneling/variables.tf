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
  default     = "inspection-forced"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Standard Firewall with management NIC, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current Firewall, VM and Bastion capacity."
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
  description = "REQUIRED approved existing Compute Gallery IMAGE VERSION ID in this subscription. Image must already contain Python3, iproute2, nftables inet/NAT, conntrack, tcpdump, systemd/cloud-init/SSH. No image building or package install is included."
  type        = string
  nullable    = false
  validation {
    condition     = try(can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Compute/galleries/[^/]+/images/[^/]+/versions/[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_id)) && lower(split("/", var.image_id)[2]) == lower(var.subscription_id), false)
    error_message = "Use a concrete approved same-subscription Compute Gallery image version ARM ID, not latest."
  }
}
variable "deploy_lab" {
  description = "False creates nothing in empty state. False after deployment destroys, not pauses."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.deploy_lab || var.image_prerequisites_confirmed
    error_message = "Deployment requires the approved prebuilt-image capability attestation."
  }
}
variable "image_prerequisites_confirmed" {
  description = "Historical attestation of preinstalled tools and approved clean guest policy, not permission or runtime proof."
  type        = bool
  default     = false
  nullable    = false
}
variable "fixtures_ready" {
  description = "Historical local origin8080/8081/8082 and app client readiness attestation, not path proof."
  type        = bool
  default     = false
  nullable    = false
}
variable "private_routes_verified" {
  description = "Historical actual A-to-F-to-E route, perimeter return and separate management evidence."
  type        = bool
  default     = false
  nullable    = false
}
variable "perimeter_ready" {
  description = "Historical local owned controller prepared/closed verification. Guest Allow is a separate explicit command, never automated by Terraform."
  type        = bool
  default     = false
  nullable    = false
}
variable "origin_access_enabled" {
  description = "Publishes only P/32 to the owned origin ports after local readiness; this is Internet-facing plain HTTP synthetic traffic."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.origin_access_enabled || (var.deploy_lab && var.fixtures_ready && var.private_routes_verified && var.perimeter_ready)
    error_message = "Origin publication requires deployment and all three readiness attestations."
  }
}
variable "test_paths_enabled" {
  description = "Opens exact client/perimeter NSG envelopes; does not open the guest or Firewall policy."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.test_paths_enabled || (var.deploy_lab && var.fixtures_ready && var.private_routes_verified && var.perimeter_ready && var.origin_access_enabled)
    error_message = "Test NSGs require prepared transport/fixtures/perimeter and restricted origin publication."
  }
}
variable "allow_test_flow" {
  description = "Firewall allows only A-to-owned-D8080/8082. Alternate8081 remains Deny."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.allow_test_flow || (var.deploy_lab && var.test_paths_enabled && var.origin_access_enabled && var.fixtures_ready && var.private_routes_verified && var.perimeter_ready)
    error_message = "Firewall Allow requires enabled exact envelopes and all readiness attestations."
  }
}
variable "snat_comparison_acknowledged" {
  description = "Explicit acknowledgement for the optional firewall_private source mode. Mode/config changes may replace VMs; isolate first, review the full plan, and re-verify new tuples."
  type        = bool
  default     = false
  nullable    = false
}
variable "source_mode" {
  description = "preserve uses policy0/0 private range; firewall_private uses default IANA private ranges so actual S in AzureFirewallSubnet is observed. Application rules are excluded. Never change mode while flows/envelopes are open."
  type        = string
  default     = "preserve"
  nullable    = false
  validation {
    condition     = contains(["preserve", "firewall_private"], var.source_mode) && (var.source_mode != "firewall_private" || var.snat_comparison_acknowledged)
    error_message = "Use preserve, or firewall_private with explicit comparison acknowledgment."
  }
}
variable "tags" {
  description = "Nonsecret ownership/cost tags only; evidence outputs are not universally redacted."
  type        = map(string)
  default     = {}
  nullable    = false
}
