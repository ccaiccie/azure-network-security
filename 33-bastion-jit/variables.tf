variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource. Check that Bastion and your VM size are available there."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 10 characters."
  type        = string
  default     = "bas33"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 10 lowercase letters or digits."
  }
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_workload" {
  description = "Gate 1. Create vm-app in the spoke (no public IP), its NSG and the hub-spoke peering. Small hourly cost."
  type        = bool
  default     = false
}

variable "deploy_bastion" {
  description = "Gate 2, COSTLY. Create the Bastion host, its public IP, a workspace and a diagnostic setting. Bastion bills per hour from creation (check current Azure pricing). Needs gate 1 and accept_bastion_cost = true."
  type        = bool
  default     = false
}

variable "accept_bastion_cost" {
  description = "Second switch for gate 2. COST WARNING: set to true only if you accept the hourly cost of a Bastion host and will destroy it in the same sitting."
  type        = bool
  default     = false
}

variable "deploy_defender_servers" {
  description = "Gate 3, COSTLY and SUBSCRIPTION-WIDE. Turn on the Defender for Servers plan (Plan 2) so JIT can be configured. It covers EVERY VM in the subscription and bills per server per month (check current pricing). Also needs accept_defender_cost = true."
  type        = bool
  default     = false
}

variable "accept_defender_cost" {
  description = "Second switch for gate 3. COST WARNING: set to true only if you accept a subscription-wide per-server monthly charge and will turn the plan off in the same sitting."
  type        = bool
  default     = false
}

variable "vm_public_ip" {
  description = "Give vm-app a TEMPORARY public IP, only for the JIT demonstration in Activity 5. Needs gate 1. Small cost. Leave false otherwise: the point of the lab is a VM with no public IP."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- Bastion options

variable "bastion_sku" {
  description = "Bastion SKU: Basic, Standard or Premium. Standard costs more than Basic (check current pricing). Native client, IP-based connection and shareable links need Standard or higher."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "bastion_sku must be Basic, Standard or Premium in this lab (Developer has no dedicated subnet and is not built here)."
  }
}

variable "bastion_native_client" {
  description = "Turn on native client support and tunnelling. Needs Standard or higher."
  type        = bool
  default     = false
}

variable "bastion_ip_connect" {
  description = "Turn on IP-based connection. Needs Standard or higher. Break/fix 4 sets it to false."
  type        = bool
  default     = false
}

variable "bastion_shareable_link" {
  description = "Allow shareable links. Needs Standard or higher. A link is a bearer capability: leave false unless you need it."
  type        = bool
  default     = false
}

variable "bastion_session_recording" {
  description = "Turn on session recording. Needs Premium and extra storage setup in the portal (check current docs)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- break/fix switches (cost nothing)

variable "bastion_nsg_include_gatewaymanager" {
  description = "Break/fix 1. When false, the inbound GatewayManager 443 rule is left out of the Bastion NSG."
  type        = bool
  default     = true
}

variable "nic_nsg_blocks_ssh" {
  description = "Break/fix 2. When true, a second NSG on the NIC denies port 22 from the Internet, shadowing a JIT allow rule in the subnet NSG."
  type        = bool
  default     = false
}

variable "peer_spoke_to_hub" {
  description = "Break/fix 3. When false, the hub and spoke are not peered and Bastion cannot reach vm-app."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------- workload and monitoring inputs

variable "admin_username" {
  description = "Admin user name for vm-app."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Public key text for vm-app (the public half is not secret). Required when deploy_workload is true."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of vm-app. Check that it is available in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace, in days."
  type        = number
  default     = 30
}
