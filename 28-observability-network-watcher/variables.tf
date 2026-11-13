variable "subscription_id" {
  description = "Subscription that holds the lab. Required; there is no default."
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
  default     = "nw28"

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
  description = "Gate 1. Create two small Linux VMs (client and server) with the Network Watcher agent. They bill by the hour."
  type        = bool
  default     = false
}

variable "deploy_monitoring" {
  description = "Gate 2. Create a Log Analytics workspace and a storage account for logs. Ingestion and storage are billed; check current pricing."
  type        = bool
  default     = false
}

variable "deploy_flow_logs" {
  description = "Gate 3. Create virtual network flow logs on the client and server VNets. Needs deploy_monitoring. Billed per GB collected; check current pricing."
  type        = bool
  default     = false
}

variable "deploy_connection_monitor" {
  description = "Gate 4. Create a Connection Monitor from the client VM to the server VM. Needs deploy_vms and deploy_monitoring. Billed per test; check current pricing."
  type        = bool
  default     = false
}

variable "deploy_firewall" {
  description = "Gate 5. Create a hub VNet with Azure Firewall Standard, a policy, user-defined routes and structured logs. Needs deploy_monitoring. EXPENSIVE: it bills by the hour."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches (cost nothing)

variable "app_port" {
  description = "TCP port the server VM listens on."
  type        = number
  default     = 8080
}

variable "nsg_allows_app_port" {
  description = "false makes NSG rule 100 a Deny for the app port. ICMP is still allowed by the default rules (break/fix 1)."
  type        = bool
  default     = true
}

variable "symmetric_return" {
  description = "With the firewall gate: true sends the server's replies through the firewall too. false leaves the server subnet without a route table, so replies bypass the firewall (break/fix 2)."
  type        = bool
  default     = true
}

variable "traffic_analytics_enabled" {
  description = "true sends flow logs to Traffic Analytics as well as to storage. false keeps storage only, so the workspace stays empty (break/fix 3)."
  type        = bool
  default     = true
}

variable "traffic_analytics_interval" {
  description = "Traffic Analytics processing interval in minutes. Allowed values are 10 and 60."
  type        = number
  default     = 10

  validation {
    condition     = contains([10, 60], var.traffic_analytics_interval)
    error_message = "traffic_analytics_interval must be 10 or 60."
  }
}

variable "monitor_protocol" {
  description = "Probe protocol of the Connection Monitor test: Tcp or Icmp (break/fix 4)."
  type        = string
  default     = "Tcp"

  validation {
    condition     = contains(["Tcp", "Icmp"], var.monitor_protocol)
    error_message = "monitor_protocol must be Tcp or Icmp."
  }
}

variable "monitor_rtt_threshold_ms" {
  description = "Round-trip time above which a check counts as failed. A very low value causes false alarms (break/fix 4)."
  type        = number
  default     = 100
}

variable "create_network_watcher" {
  description = "false uses the regional Network Watcher that Azure created automatically. true creates one; set it only if your subscription has none."
  type        = bool
  default     = false
}

variable "vm_size" {
  description = "Size of the two lab VMs. Check capacity in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "Text of an SSH public key (not a path). Needed with deploy_vms. Never put a private key here."
  type        = string
  default     = ""
}
