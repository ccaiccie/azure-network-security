variable "subscription_id" {
  description = "Subscription that will own the lab. Use a disposable one."
  type        = string
}

variable "location" {
  description = "Primary region for everything except the optional second region."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the new resource group that holds everything."
  type        = string
  default     = "std-lb-lab"
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

variable "frontend_zones" {
  description = "Zones for the frontend IP configurations. Three zones = zone-redundant. Use [] in a region without availability zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

# ---------------------------------------------------------------- behaviour settings (safe, free)

variable "session_persistence" {
  description = "Distribution mode of the main rule: Default (5-tuple), SourceIP (2-tuple) or SourceIPProtocol (3-tuple)."
  type        = string
  default     = "Default"

  validation {
    condition     = contains(["Default", "SourceIP", "SourceIPProtocol"], var.session_persistence)
    error_message = "session_persistence must be Default, SourceIP or SourceIPProtocol."
  }
}

variable "floating_ip" {
  description = "Floating IP (direct server return) on the main rule. Also puts the frontend address on the guests' loopback."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- gates (all false)

variable "deploy_vms" {
  description = "Gate 1. Deploy vm-web1, vm-web2 and vm-client. VMs and disks cost money while they exist."
  type        = bool
  default     = false
}

variable "enable_ha_ports_rule" {
  description = "Gate 2. Add a second frontend (10.23.1.11) with an HA ports rule on the same pool."
  type        = bool
  default     = false
}

variable "create_nat_rule" {
  description = "Gate 3. Add an inbound NAT rule that maps frontend TCP 2201 to vm-web1 port 22."
  type        = bool
  default     = false
}

variable "create_public_lb" {
  description = "Gate 4. COSTS and exposes TCP 80 to the Internet. Create a public IP and a public Standard load balancer on the same two VMs."
  type        = bool
  default     = false
}

variable "create_global_lb" {
  description = "Gate 5. COSTS. Create a global (cross-region) load balancer in front of the public one. Needs create_public_lb."
  type        = bool
  default     = false
}

variable "break_fix" {
  description = "Break/fix switch: none, probe_port, nsg_probe or affinity. Each value builds one broken setup on purpose."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "probe_port", "nsg_probe", "affinity"], var.break_fix)
    error_message = "break_fix must be none, probe_port, nsg_probe or affinity."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = { purpose = "disposable-standard-lb-lab" }
}
