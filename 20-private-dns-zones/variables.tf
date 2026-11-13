variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every regional resource. DNS zones are global."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "dns20"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 10 lowercase letters or digits."
  }
}

variable "zone_name" {
  description = "Name of the private zone, and of the public zone when gate 4 is open. Use a name you do not own, such as lab20.example."
  type        = string
  default     = "lab20.example"
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_vms" {
  description = "Gate 1. Create vm-app-1 and vm-spoke-1 (billable). Without it the lab is only free DNS and network objects."
  type        = bool
  default     = false
}

variable "deploy_custom_dns" {
  description = "Gate 2. Create the dns-fwd forwarder VM (billable) and set it as the DNS server of the app VNet."
  type        = bool
  default     = false
}

variable "deploy_private_endpoint" {
  description = "Gate 3. Create a storage account, a blob private endpoint, the privatelink.blob.core.windows.net zone and its links."
  type        = bool
  default     = false
}

variable "create_public_zone" {
  description = "Gate 4. Create a public Azure DNS zone with the same name as the private zone, for the split-horizon test. It is not delegated, so the Internet never asks it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- break/fix selector (one value at a time)

variable "break_fix" {
  description = "Break/fix selector: none, no_spoke_link, no_zone_group, pe_zone_unlinked, public_forwarder or stale_record. Use none for the working design."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "no_spoke_link", "no_zone_group", "pe_zone_unlinked", "public_forwarder", "stale_record"], var.break_fix)
    error_message = "break_fix must be none, no_spoke_link, no_zone_group, pe_zone_unlinked, public_forwarder or stale_record."
  }
}

variable "vm_size" {
  description = "Size of the lab VMs. Check current prices and availability in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "SSH public key (the .pub text) for the lab VMs. Needed only when deploy_vms or deploy_custom_dns is true. A public key is not a secret."
  type        = string
  default     = ""
}
