variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Region of hub 1 and of everything in region 1."
  type        = string
  default     = "westeurope"
}

variable "location2" {
  description = "Region of hub 2 (only used when gate 5 is open)."
  type        = string
  default     = "northeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits, 3 to 10 characters."
  type        = string
  default     = "vwan32"

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

variable "deploy_hub1" {
  description = "Gate 1. Create virtual hub 1, its custom route tables and the three VNet connections. A Standard hub bills by the hour and takes a while to create."
  type        = bool
  default     = false
}

variable "deploy_vms" {
  description = "Gate 2. Create small test VMs in the spokes (billable, no public IPs). Needs admin_ssh_public_key."
  type        = bool
  default     = false
}

variable "deploy_branch_sim" {
  description = "Gate 3. Create the simulated branch VNet with vm-edge (strongSwan and FRR) and vm-lan (billable). Needs admin_ssh_public_key."
  type        = bool
  default     = false
}

variable "deploy_vpn" {
  description = "Gate 4. Create the hub 1 VPN gateway, the VPN site and the connection with BGP. Needs gates 1 and 3 and a shared_key. Scale units bill by the hour."
  type        = bool
  default     = false
}

variable "deploy_hub2" {
  description = "Gate 5. Create virtual hub 2 in the second region with its route tables and one VNet connection. A second hub doubles the hub cost."
  type        = bool
  default     = false
}

variable "deploy_er_gateway" {
  description = "Gate 6. Create an ExpressRoute gateway in hub 1. It bills by scale unit even without a circuit. The lab creates no circuit."
  type        = bool
  default     = false
}

variable "deploy_nva_bgp" {
  description = "Gate 7. Create vm-nva in the shared spoke (FRR) and a BGP connection from hub 1 to it. Needs gates 1 and 2."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches that cost nothing

variable "fault" {
  description = "Break/fix switch for Activity 8: none, label_typo, shared_none or branch_assoc_default."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "label_typo", "shared_none", "branch_assoc_default"], var.fault)
    error_message = "fault must be none, label_typo, shared_none or branch_assoc_default."
  }
}

variable "hub_routing_preference" {
  description = "Hub routing preference for hub 1: ExpressRoute, VpnGateway or ASPath. Check current docs for the exact accepted values."
  type        = string
  default     = "ExpressRoute"
}

variable "allow_branch_to_branch" {
  description = "Virtual WAN setting: let branches (VPN and ExpressRoute) reach each other through the hub."
  type        = bool
  default     = true
}

variable "static_routes" {
  description = "Add the static route in the rt-spokes table (10.251.0.0/24 via the shared connection) and the static route on the shared VNet connection (10.250.0.0/24 via vm-nva 10.103.0.10)."
  type        = bool
  default     = false
}

variable "vpn_scale_unit" {
  description = "Scale units of the hub VPN gateway. One unit is a fixed slice of throughput; check current docs."
  type        = number
  default     = 1
}

variable "er_scale_units" {
  description = "Scale units of the hub ExpressRoute gateway."
  type        = number
  default     = 1
}

variable "er_circuit_peering_id" {
  description = "Optional resource ID of an existing ExpressRoute circuit private peering. Empty (default) means no ExpressRoute connection is created."
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "Admin user of the lab VMs."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Text of an SSH public key (not secret). Needed when gate 2, 3 or 7 is open."
  type        = string
  default     = ""
}

variable "shared_key" {
  description = "Pre-shared key of the VPN link. Lab-only, 16 or more characters. It lands in state and in VM custom data, so never reuse a real key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "vm_size" {
  description = "Size of every lab VM."
  type        = string
  default     = "Standard_B1s"
}
