variable "subscription_id" {
  description = "Subscription that holds the lab and is the scope of the network manager. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "westeurope"
}

variable "secondary_location" {
  description = "Second region, used only when deploy_second_region is true."
  type        = string
  default     = "northeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "avnm25"

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

variable "deploy_avnm" {
  description = "Gate 1. Create the network manager (scope: this subscription) and the static network group with spoke-a and spoke-b. Nothing is committed yet."
  type        = bool
  default     = false
}

variable "deploy_connectivity" {
  description = "Gate 2. Create two hub-and-spoke connectivity configurations and commit the one chosen by active_connectivity. Needs deploy_avnm. Creates peerings: check current pricing."
  type        = bool
  default     = false
}

variable "deploy_security_admin" {
  description = "Gate 3. Create a security admin configuration with one collection and two rules, and commit it. Needs deploy_avnm."
  type        = bool
  default     = false
}

variable "deploy_dynamic_group" {
  description = "Gate 4. Create a second network group fed by an Azure Policy (tag env = prod). Needs deploy_avnm. Creates a custom policy and a subscription-level assignment."
  type        = bool
  default     = false
}

variable "deploy_vms" {
  description = "Gate 5. Create three small Linux VMs (spoke-a, spoke-b, spoke-c) and an NSG. VM b serves HTTP on app_port. Billable."
  type        = bool
  default     = false
}

variable "deploy_second_region" {
  description = "Gate 6. Create spoke-d in secondary_location (a free VNet). Used to show regional deployments."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches changed during the activities

variable "active_connectivity" {
  description = "Which connectivity configuration is committed: v1 (hub-and-spoke, spokes not directly connected) or v2 (same, with direct connectivity inside the group). Deploying v1 again is the rollback."
  type        = string
  default     = "v1"

  validation {
    condition     = contains(["v1", "v2"], var.active_connectivity)
    error_message = "active_connectivity must be v1 or v2."
  }
}

variable "delete_existing_peering" {
  description = "Connectivity configuration setting: remove existing peerings between the managed VNets when the configuration is deployed."
  type        = bool
  default     = true
}

variable "use_hub_gateway" {
  description = "Connectivity configuration setting: spokes use the hub's gateway. Leave false: the lab hub has no gateway, and true would fail or do nothing useful."
  type        = bool
  default     = false
}

variable "deployment_regions" {
  description = "Regions the committed configurations are deployed to. Add secondary_location in Activity 6."
  type        = list(string)
  default     = ["westeurope"]
}

variable "admin_rule_action" {
  description = "Action of the security admin rule on app_port: Allow, Deny or AlwaysAllow."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny", "AlwaysAllow"], var.admin_rule_action)
    error_message = "admin_rule_action must be Allow, Deny or AlwaysAllow."
  }
}

variable "nsg_allows_app_port" {
  description = "true: the NSG on the spoke subnets allows app_port inbound. false: the NSG denies it."
  type        = bool
  default     = true
}

variable "app_port" {
  description = "TCP port that vm-b serves and that the admin rule and the NSG talk about."
  type        = number
  default     = 8080
}

variable "spoke_c_env" {
  description = "Value of the env tag on spoke-c. The dynamic group selects env = prod, so setting this to prod makes spoke-c join it."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------- VMs

variable "vm_size" {
  description = "Size of the lab VMs. Check that it is available in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "Public key text (not a path) for the labadmin account. Needed when deploy_vms is true."
  type        = string
  default     = ""
}
