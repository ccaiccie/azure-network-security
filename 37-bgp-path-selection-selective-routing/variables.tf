variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource. Route Server and the VPN gateway must be available there; check current docs."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "bgp37"

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

variable "deploy_route_server" {
  description = "Gate 1. Create Azure Route Server and its Standard public IP. Billed by the hour; check current pricing."
  type        = bool
  default     = false
}

variable "deploy_nvas" {
  description = "Gate 2. Create two small FRR VMs (nva-a, nva-b), their public IPs, the Route Server peerings and vm-app. Billable. Needs gate 1."
  type        = bool
  default     = false
}

variable "deploy_vpn_gateway" {
  description = "Gate 3, optional. Create a BGP-enabled VPN gateway in GatewaySubnet. Billed by the hour and slow (30 to 45 minutes or more). Needs gate 1 for the branch-to-branch exercise."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- free switches (change during the activities)

variable "branch_to_branch" {
  description = "Route Server branch-to-branch setting. When true, Route Server also exchanges routes with a VPN or ExpressRoute gateway in the same VNet. Activity 7."
  type        = bool
  default     = false
}

variable "app_bgp_route_propagation" {
  description = "Whether the workload route table accepts BGP-learned routes (route propagation). Activity 7 sets it to false."
  type        = bool
  default     = true
}

variable "blackhole_prefix" {
  description = "A prefix to send to next hop None on the workload route table. Empty means no such route. Activity 7 uses 10.99.9.0/24."
  type        = string
  default     = ""
}

variable "nva_a_asn" {
  description = "Private ASN of nva-a. Must not be 65515 to 65520 (Azure reserved; check current docs)."
  type        = number
  default     = 65001
}

variable "nva_b_asn" {
  description = "Private ASN of nva-b. Different from nva-a so AS paths differ. Break/fix 3 sets it to 65515 on purpose."
  type        = number
  default     = 65002
}

variable "vpn_sku" {
  description = "VPN gateway SKU for gate 3. Check current Microsoft docs for which SKUs can be created."
  type        = string
  default     = "VpnGw1AZ"
}

variable "azure_bgp_asn" {
  description = "ASN of the VPN gateway when gate 3 is open. Avoid the Azure-reserved ASNs."
  type        = number
  default     = 65010
}

variable "vm_size" {
  description = "Size of the lab VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "Public key text for the lab VMs (not a secret). Required when gate 2 is open."
  type        = string
  default     = ""
}
