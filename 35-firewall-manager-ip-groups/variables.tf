variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource. Check that Azure Firewall is available there."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 10 characters."
  type        = string
  default     = "fm35"

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

variable "deploy_firewall" {
  description = "Gate 1, COSTLY. Create a hub VNet, a Standard public IP and ONE Azure Firewall that uses the parent or a child policy. Azure Firewall bills per hour from creation (check current Azure pricing). Needs accept_firewall_cost = true."
  type        = bool
  default     = false
}

variable "accept_firewall_cost" {
  description = "Second switch for gate 1. COST WARNING: set to true only if you accept the hourly firewall cost plus data processing and will destroy the firewall in the same sitting."
  type        = bool
  default     = false
}

variable "deploy_analytics" {
  description = "Gate 2. Create a Log Analytics workspace, turn on policy insights on the parent policy and add a firewall diagnostic setting with resource-specific tables. Log ingestion has a small cost (check current pricing). The diagnostic setting needs gate 1."
  type        = bool
  default     = false
}

variable "deploy_policy_audit" {
  description = "Gate 3. Create a custom Azure Policy definition that AUDITS firewalls not using the approved policy, assigned at the lab resource group only (effect audit, nothing is denied). Free."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- policy options

variable "policy_sku" {
  description = "Firewall policy tier: Standard or Premium. Premium adds IDPS and TLS inspection and is needed for a Premium firewall (check current pricing). A firewall must match its policy tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.policy_sku)
    error_message = "policy_sku must be Standard or Premium."
  }
}

variable "firewall_policy_choice" {
  description = "Which policy the gated firewall uses: child-a, child-b or parent."
  type        = string
  default     = "child-a"

  validation {
    condition     = contains(["child-a", "child-b", "parent"], var.firewall_policy_choice)
    error_message = "firewall_policy_choice must be child-a, child-b or parent."
  }
}

variable "dnat_public_ip" {
  description = "Public address used in the DNAT rule. The default is an RFC 5737 example; with gate 1 open, use the firewall public IP from the outputs."
  type        = string
  default     = "203.0.113.10"
}

# ---------------------------------------------------------------- break/fix switches (cost nothing)

variable "child_allow_blocked_range" {
  description = "Break/fix 1. Add a child rule that allows 198.51.100.0/24, which the parent denies first. The child rule never matches."
  type        = bool
  default     = false
}

variable "ipg_app_a_missing_prefix" {
  description = "Break/fix 2. Leave 10.61.2.0/24 out of ipg-app-a, so traffic from the new subnet matches no allow rule."
  type        = bool
  default     = false
}

variable "associate_policy_to_firewall" {
  description = "Break/fix 3. Needs gate 1. Set to false to create the firewall WITHOUT any policy association."
  type        = bool
  default     = true
}

variable "child_conflicting_dnat" {
  description = "Break/fix 4. Add a child DNAT rule for the same public IP and port as the parent DNAT rule, with a different target."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the lab workspace (gate 2)."
  type        = number
  default     = 30
}
