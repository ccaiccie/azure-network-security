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
  default     = "inspection-pe"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Standard Firewall, PE NSG support, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
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
  description = "REQUIRED approved existing Compute Gallery IMAGE VERSION ID in this subscription. Image must already contain Python3 with SSL/default public CA roots, iproute2, dig, systemd/cloud-init/SSH. No image building or package install is included."
  type        = string
  nullable    = false
  validation {
    condition     = try(can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Compute/galleries/[^/]+/images/[^/]+/versions/[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_id)) && lower(split("/", var.image_id)[2]) == lower(var.subscription_id), false)
    error_message = "Use a concrete approved same-subscription Compute Gallery image version ARM ID, not latest."
  }
}
variable "storage_account_name" {
  description = "Required globally unique NEW lowercase alphanumeric StorageV2 account name, no sensitive text."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use 3-24 lowercase alphanumeric characters for a new globally unique account."
  }
}
variable "deploy_lab" {
  description = "Creates two VM system identities and owned substrate only after explicit future approval; false after deployment destroys, not pauses."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.deploy_lab || (var.image_prerequisites_confirmed && var.identity_access_authorized)
    error_message = "deploy_lab requires its prerequisite gates; see the staged runbook."
  }
}
variable "image_prerequisites_confirmed" {
  description = "Historical approved image and public CA/root/DNS tool readiness attestation."
  type        = bool
  default     = false
  nullable    = false
}
variable "identity_access_authorized" {
  description = "Explicit operator attestation of separately approved system-identity creation and requested container-scoped role grants. Not automatic permission."
  type        = bool
  default     = false
  nullable    = false
}
variable "pe_ready" {
  description = "Historical Approved owned Blob PE target/subresource/address/policy observation, not IP-only proof."
  type        = bool
  default     = false
  nullable    = false
}
variable "dns_enabled" {
  description = "Enable only UDP/TCP53 from client VMs to F for DNS verification."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.dns_enabled || (var.deploy_lab && var.pe_ready)
    error_message = "dns_enabled requires its prerequisite gates; see the staged runbook."
  }
}
variable "dns_verified" {
  description = "Historical ordinary Blob hostname resolves only E and Firewall-side DNS consistency evidence."
  type        = bool
  default     = false
  nullable    = false
}
variable "routes_verified" {
  description = "Historical client E/32 steering and direct competitor/onward route evidence."
  type        = bool
  default     = false
  nullable    = false
}
variable "pe_ingress_enabled" {
  description = "Enable only FirewallSubnet proxy-source envelope to E443."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.pe_ingress_enabled || (var.deploy_lab && var.pe_ready && var.dns_enabled && var.dns_verified && var.routes_verified && var.pe_network_policies == "Enabled" && var.install_pe_host_route)
    error_message = "pe_ingress_enabled requires its prerequisite gates; see the staged runbook."
  }
}
variable "client_paths_enabled" {
  description = "Enable reader A443 envelope independently of application Allow."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.client_paths_enabled || var.pe_ingress_enabled
    error_message = "client_paths_enabled requires its prerequisite gates; see the staged runbook."
  }
}
variable "seed_paths_enabled" {
  description = "Enable separate seed VM443 envelope independently of application Allow."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.seed_paths_enabled || var.pe_ingress_enabled
    error_message = "seed_paths_enabled requires its prerequisite gates; see the staged runbook."
  }
}
variable "allow_client_blob" {
  description = "Exact reader application collection Allow; no-auth and authorized tests remain distinct."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.allow_client_blob || var.client_paths_enabled
    error_message = "allow_client_blob requires its prerequisite gates; see the staged runbook."
  }
}
variable "allow_seed_blob" {
  description = "Exact seed application collection Allow for separately approved seed operation."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.allow_seed_blob || (var.seed_paths_enabled && var.grant_seed_role)
    error_message = "allow_seed_blob requires its prerequisite gates; see the staged runbook."
  }
}
variable "grant_reader_role" {
  description = "Create only reader VM system identity Storage Blob Data Reader role at owned container scope."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.grant_reader_role || (var.deploy_lab && var.identity_access_authorized)
    error_message = "grant_reader_role requires its prerequisite gates; see the staged runbook."
  }
}
variable "grant_seed_role" {
  description = "Create only seed VM system identity Storage Blob Data Contributor at owned container scope; revoke after seeding."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.grant_seed_role || (var.deploy_lab && var.identity_access_authorized)
    error_message = "grant_seed_role requires its prerequisite gates; see the staged runbook."
  }
}
variable "isolation_verified" {
  description = "Historical stopped requests/closed application and both client/PE envelopes verified before route experiment."
  type        = bool
  default     = false
  nullable    = false
}
variable "route_experiment_acknowledged" {
  description = "Explicit isolated configuration-only route/policy experiment acknowledgment."
  type        = bool
  default     = false
  nullable    = false
}
variable "pe_network_policies" {
  description = "PE-hosting subnet policies, not Private Link Service policy. Nonbaseline modes only in verified isolated read-only route experiments."
  type        = string
  default     = "Enabled"
  nullable    = false
  validation {
    condition     = contains(["Enabled", "Disabled", "RouteTableEnabled", "NetworkSecurityGroupEnabled"], var.pe_network_policies) && (var.pe_network_policies == "Enabled" || (var.deploy_lab && var.route_experiment_acknowledged && var.isolation_verified && !var.pe_ingress_enabled && !var.client_paths_enabled && !var.seed_paths_enabled && !var.allow_client_blob && !var.allow_seed_blob))
    error_message = "Use Enabled baseline, or a supported enum only with all flow gates closed and explicit isolation/experiment acknowledgment."
  }
}
variable "install_pe_host_route" {
  description = "True installs exact E/32 to F; false is an isolated route observation experiment, never a live bypass test."
  type        = bool
  default     = true
  nullable    = false
  validation {
    condition     = var.install_pe_host_route || (var.deploy_lab && var.route_experiment_acknowledged && var.isolation_verified && !var.pe_ingress_enabled && !var.client_paths_enabled && !var.seed_paths_enabled && !var.allow_client_blob && !var.allow_seed_blob)
    error_message = "Removing E/32 requires isolated closed envelopes and explicit route experiment acknowledgment."
  }
}
variable "tags" {
  description = "Nonsecret cost/owner tags only; collector outputs are not automatically redacted."
  type        = map(string)
  default     = {}
  nullable    = false
}
