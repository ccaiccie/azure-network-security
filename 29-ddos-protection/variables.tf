variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource. Pick a region that has availability zones: the public IPs are zone-redundant."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 10 characters."
  type        = string
  default     = "ddos29"

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
  description = "Gate 1. Create vm-web, the Standard public IP pip-web (attached) and pip-spare (attached to nothing). Small hourly cost."
  type        = bool
  default     = false
}

variable "deploy_monitoring" {
  description = "Gate 2. Create the Log Analytics workspace, a diagnostic setting on pip-web, an action group and a metric alert. Needs gate 1. Small ingestion cost."
  type        = bool
  default     = false
}

variable "deploy_ddos_network_protection" {
  description = "Gate 3, COSTLY. Create a DDoS protection plan and link the VNet to it. A plan costs roughly thousands of US dollars per month and bills from creation (check current Azure pricing). Also needs accept_ddos_plan_cost = true."
  type        = bool
  default     = false
}

variable "accept_ddos_plan_cost" {
  description = "Second switch for gate 3. COST WARNING: set to true only if you accept the monthly cost of a DDoS protection plan and will destroy it in the same sitting."
  type        = bool
  default     = false
}

variable "deploy_ip_protection" {
  description = "Gate 4, COSTLY. Enable DDoS IP Protection on pip-web (protection mode Enabled, no plan). Billed per protected IP per month (check current pricing). Needs gate 1. The lab refuses to enable it together with gate 3."
  type        = bool
  default     = false

  validation {
    condition     = !(var.deploy_ip_protection && var.deploy_ddos_network_protection)
    error_message = "Choose one paid tier in the lab: either deploy_ddos_network_protection or deploy_ip_protection, not both."
  }
}

# ---------------------------------------------------------------- break/fix switches (cost nothing)

variable "link_vnet_to_plan" {
  description = "Break/fix 4. When false, the plan is created but the VNet is not linked to it, so nothing is protected."
  type        = bool
  default     = true
}

variable "pip_web_mode_override" {
  description = "Break/fix 2 and 4. Empty means: Enabled with gate 4, else VirtualNetworkInherited. Or set Enabled, Disabled or VirtualNetworkInherited explicitly."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "Enabled", "Disabled", "VirtualNetworkInherited"], var.pip_web_mode_override)
    error_message = "pip_web_mode_override must be empty, Enabled, Disabled or VirtualNetworkInherited."
  }
}

variable "alert_on_spare_ip_by_mistake" {
  description = "Break/fix 3. When true, the attack alert is scoped to pip-spare instead of pip-web, so it can never fire."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- workload and monitoring inputs

variable "admin_username" {
  description = "Admin user name for vm-web."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Public key text for vm-web (the public half is not secret). Required when deploy_workload is true. Nothing opens SSH: the lab uses az vm run-command."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of vm-web. Check that it is available in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "alert_email" {
  description = "Address that receives the attack alert. The default is a documentation address nobody reads: set your own."
  type        = string
  default     = "ops@example.com"
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace, in days."
  type        = number
  default     = 30
}
