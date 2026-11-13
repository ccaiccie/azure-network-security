variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "nsg19"

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

variable "deploy_vms" {
  description = "Gate 1. Create the two small Linux VMs and their NICs (billable). Without it the lab is only free network objects."
  type        = bool
  default     = false
}

variable "attach_nic_nsg" {
  description = "Gate 2. Attach a second NSG to the app VM's NIC (needs deploy_vms). Shows the NIC layer after the subnet layer."
  type        = bool
  default     = false
}

variable "deploy_private_endpoint" {
  description = "Gate 3. Create a storage account, a blob private endpoint and the pe subnet NSG (small hourly cost)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Gate 4. Create a storage account and a virtual network flow log (billable per log volume)."
  type        = bool
  default     = false
}

variable "enable_avnm_demo" {
  description = "Gate 5. Create a Virtual Network Manager with one security admin rule and deploy it. Affects every VNet in its network group, so keep it false unless you read the plan."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches used by the activities

variable "web_nic_in_asg" {
  description = "Activity 5. true: the web VM's NIC is a member of asg-web. false: it is removed, so every rule that names asg-web stops matching it."
  type        = bool
  default     = true
}

variable "pe_network_policies" {
  description = "Activity 6. Network policies on the pe subnet: Disabled, Enabled, NetworkSecurityGroupEnabled or RouteTableEnabled. Check the current provider and Azure docs for the exact values."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], var.pe_network_policies)
    error_message = "pe_network_policies must be Disabled, Enabled, NetworkSecurityGroupEnabled or RouteTableEnabled."
  }
}

variable "vm_size" {
  description = "Size of the two lab VMs. Check current prices and availability in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "SSH public key (the .pub text) for the lab VMs. Needed only when deploy_vms is true. A public key is not a secret."
  type        = string
  default     = ""
}

variable "flow_log_retention_days" {
  description = "Days to keep flow log blobs. 0 means keep forever; check current docs."
  type        = number
  default     = 7
}
