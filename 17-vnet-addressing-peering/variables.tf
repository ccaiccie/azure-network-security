variable "subscription_id" {
  description = "Subscription that will own the lab. Use a disposable one."
  type        = string
}

variable "location" {
  description = "Primary region for the hub, spoke-a and spoke-b."
  type        = string
  default     = "westeurope"
}

variable "secondary_location" {
  description = "A different region for spoke-c. Only used when create_global_peering is true."
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Name of the new resource group that holds everything."
  type        = string
  default     = "vnet-peering-lab"
}

variable "admin_ssh_public_key" {
  description = "An existing OpenSSH public key. Needed only when deploy_vms is true."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size for the small test VMs. Check current regional availability."
  type        = string
  default     = "Standard_B1s"
}

# ---------------------------------------------------------------- gates (all false)

variable "deploy_vms" {
  description = "Gate 1. Deploy the test VMs (vm-a, vm-b, vm-hub). VMs and disks cost money while they exist."
  type        = bool
  default     = false
}

variable "peer_spokes_directly" {
  description = "Gate 2. Add a direct peering between spoke-a and spoke-b (fix 1 for non-transitivity)."
  type        = bool
  default     = false
}

variable "deploy_nva" {
  description = "Gate 3. Deploy a forwarding Linux VM in the hub, route tables on the spokes and allow forwarded traffic on the spoke peerings (fix 2)."
  type        = bool
  default     = false
}

variable "create_global_peering" {
  description = "Gate 4. Create spoke-c in the secondary region and peer it with the hub (global peering)."
  type        = bool
  default     = false
}

variable "create_gateway" {
  description = "Gate 5. COSTLY. Create a VpnGw1AZ gateway and its public IP in the hub. Provisioning commonly takes 30 minutes or more."
  type        = bool
  default     = false
}

variable "enable_gateway_transit" {
  description = "Gate 6. Hub peerings allow gateway transit and spoke-a uses the remote gateway. Needs create_gateway."
  type        = bool
  default     = false
}

variable "create_onprem_connection" {
  description = "Gate 7. Create a local network gateway (192.168.100.0/24) and an IPsec connection so on-premises routes exist. Needs create_gateway and vpn_shared_key."
  type        = bool
  default     = false
}

variable "vpn_shared_key" {
  description = "Pre-shared key for the connection. Supply it through TF_VAR_vpn_shared_key, never in a file. It is kept in Terraform state."
  type        = string
  default     = null
  sensitive   = true
}

variable "break_fix" {
  description = "Break/fix switch: none, one_sided, no_forwarded, no_transit or overlap. Each value builds one broken setup on purpose."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "one_sided", "no_forwarded", "no_transit", "overlap"], var.break_fix)
    error_message = "break_fix must be none, one_sided, no_forwarded, no_transit or overlap."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = { purpose = "disposable-vnet-peering-lab" }
}
