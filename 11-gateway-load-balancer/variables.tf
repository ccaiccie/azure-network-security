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
  default     = "inspection-gwlb"
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]$", var.resource_group_name))
    error_message = "Use 3-90 letters, digits, hyphens or underscores, ending with a letter or digit."
  }
}

variable "location" {
  description = "REQUIRED approved Azure region with Gateway and Standard Load Balancer, Bastion and selected VM capacity. No default; verify current Standard capacity restrictions."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use the approved available Azure region identifier, after checking current Load Balancer, VM and Bastion capacity."
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
  description = "Available x64 VM size supporting the chosen approved Linux image; check quota, region and pricing."
  type        = string
  default     = "Standard_B1s"
  nullable    = false
  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.vm_size))
    error_message = "Supply an Azure Standard VM SKU."
  }
}

variable "image_id" {
  description = "REQUIRED approved existing Compute Gallery IMAGE VERSION ID in this subscription. Image must already contain Python3, iproute2 with VXLAN/bridge support, nftables bridge family, tcpdump, systemd/cloud-init/SSH. No image building or package install is included."
  type        = string
  nullable    = false
  validation {
    condition     = try(can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Compute/galleries/[^/]+/images/[^/]+/versions/[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_id)) && lower(split("/", var.image_id)[2]) == lower(var.subscription_id), false)
    error_message = "Use a concrete approved same-subscription Compute Gallery image version ARM ID, not latest."
  }
}
variable "client_public_ip" {
  type        = string
  nullable    = false
  description = "REQUIRED separately authorized external client stable public IPv4, bare address. Never use an assistant host or unapproved third party."
  validation {
    condition     = try(can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.client_public_ip)) && cidrhost("${var.client_public_ip}/32", 0) == var.client_public_ip && alltrue([for p in ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"] : cidrhost("${var.client_public_ip}/${split("/", p)[1]}", 0) != cidrhost(p, 0)]), false)
    error_message = "Use an actual globally routable external client IPv4, not private/shared/documentation/reserved/multicast."
  }
}
variable "image_prerequisites_confirmed" {
  type        = bool
  default     = false
  nullable    = false
  description = "Attestation for approved immutable image/kernel/tool/MTU capabilities. No package bootstrap provided."
}
variable "deploy_lab" {
  type        = bool
  default     = false
  nullable    = false
  description = "False creates nothing in empty state. False after deployment plans destruction, not pause."
  validation {
    condition     = !var.deploy_lab || var.image_prerequisites_confirmed
    error_message = "Deployment requires approved image prerequisites."
  }
}
variable "appliances_ready" {
  type        = bool
  default     = false
  nullable    = false
  description = "Historical attestation: BOTH owned NVAs are prepared closed and independently verified, with readiness advertised. Not runtime proof or permission."
}
variable "application_ready" {
  type        = bool
  default     = false
  nullable    = false
  description = "Historical attestation for both backend fixtures and independent app health."
}
variable "enable_chain" {
  type        = bool
  default     = false
  nullable    = false
  description = "Attach consumer frontend to GWLB only after both readiness attestations. Detach only after separately verified isolation; not an automatic rollback."
  validation {
    condition     = !var.enable_chain || (var.deploy_lab && var.appliances_ready && var.application_ready)
    error_message = "Chain activation requires deployed substrate and verified appliance/application readiness."
  }
}
variable "test_paths_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Open exact client/32 to B8080/8081 NSG envelope only with chain active. Guest bridge remains independently closed until explicit local action."
  validation {
    condition     = !var.test_paths_enabled || (var.enable_chain && var.appliances_ready && var.application_ready)
    error_message = "Test ingress requires an active approved chain and both readiness attestations."
  }
}
