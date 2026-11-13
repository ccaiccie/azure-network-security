variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default. Also used in the Private Link Service visibility and auto-approval lists."
  type        = string
}

variable "location" {
  description = "Azure region for every regional resource."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 8 characters (storage account names are short)."
  type        = string
  default     = "pl27"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 8 lowercase letters or digits."
  }
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

variable "admin_source_ip" {
  description = "Optional public IP of your workstation, added to the storage firewall IP rules so Terraform can still read the account while the firewall is Deny. Leave empty if you do not need it. Use a plain address, not a range."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_vms" {
  description = "Gate 1. Create vm-se-1 and vm-plain-1 in the consumer VNet (billable)."
  type        = bool
  default     = false
}

variable "deploy_storage" {
  description = "Gate 2. Create the lab storage account with the firewall set to Deny, the VNet rule for snet-se and a public test container."
  type        = bool
  default     = false
}

variable "deploy_private_endpoint" {
  description = "Gate 3 (needs gate 2). Create the blob private endpoint, the privatelink.blob.core.windows.net zone, its link and the zone group. The endpoint bills by the hour."
  type        = bool
  default     = false
}

variable "deploy_se_policy" {
  description = "Gate 4. Create a service endpoint policy on snet-se and a second, unrelated storage account in its own resource group, to test exfiltration."
  type        = bool
  default     = false
}

variable "deploy_pls" {
  description = "Gate 5 (needs gate 1 to test). Create the provider VNet pieces (backend VM, Standard internal load balancer, Private Link Service) and a consumer private endpoint to it. Billable."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches

variable "disable_public_access" {
  description = "Stage 4 switch. Set public network access of the lab storage account to Disabled. Service endpoints then stop working; the private endpoint keeps working."
  type        = bool
  default     = false
}

variable "attach_se_policy" {
  description = "Stage 5 switch (needs gate 4). Attach the service endpoint policy to snet-se. Created but unattached policies do nothing."
  type        = bool
  default     = false
}

variable "pe_nsg_deny_se" {
  description = "Stage 3 switch. Add a rule to the NSG on snet-pe that denies TCP 443 from snet-se. Whether it takes effect depends on the subnet network policies."
  type        = bool
  default     = false
}

variable "enable_proxy_protocol" {
  description = "Stage 5 switch. Turn on TCP proxy protocol v2 on the Private Link Service. The lab backend understands both modes."
  type        = bool
  default     = false
}

variable "pls_nat_ip_count" {
  description = "Number of NAT IP configurations on the Private Link Service, 1 to 8. The NAT subnet is a /28, which has 11 usable addresses."
  type        = number
  default     = 1

  validation {
    condition     = var.pls_nat_ip_count >= 1 && var.pls_nat_ip_count <= 8
    error_message = "pls_nat_ip_count must be between 1 and 8."
  }
}

# ---------------------------------------------------------------- break/fix selector (one value at a time)

variable "break_fix" {
  description = "Break/fix selector: none, public_open, pe_pending, zone_unlinked, pls_pending or nsg_ignored. Use none for the working design."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "public_open", "pe_pending", "zone_unlinked", "pls_pending", "nsg_ignored"], var.break_fix)
    error_message = "break_fix must be none, public_open, pe_pending, zone_unlinked, pls_pending or nsg_ignored."
  }
}

variable "vm_size" {
  description = "Size of the lab VMs. Check current prices and availability in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "SSH public key (the .pub text) for the lab VMs. Needed only when deploy_vms or deploy_pls is true. A public key is not a secret."
  type        = string
  default     = ""
}
