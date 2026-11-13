# REFERENCE SKELETON. Every gate defaults to false, so a plain apply creates nothing.

variable "subscription_id" {
  description = "Subscription that will hold the skeleton. Required; there is no default."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 8 characters."
  type        = string
  default     = "cap36"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 8 lowercase letters or digits."
  }
}

variable "location_a" {
  description = "Region A. Check current docs for the SKUs and zones you plan to use there."
  type        = string
  default     = "westeurope"
}

variable "location_b" {
  description = "Region B, the paired or second region for the design."
  type        = string
  default     = "northeurope"
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_region_a" {
  description = "Gate 1. Region A: resource group, hub VNet and subnets, three spoke VNets, route tables, NSG. VNets are free; check current pricing for the rest."
  type        = bool
  default     = false
}

variable "deploy_region_b" {
  description = "Gate 2. Region B: the mirror of region A with the 10.22 address block."
  type        = bool
  default     = false
}

variable "enable_peering" {
  description = "Gate 3. Hub-to-spoke peerings in each deployed region, and the global hub-to-hub peering when both regions exist."
  type        = bool
  default     = false
}

variable "deploy_firewall_policy" {
  description = "Gate 4. One base Azure Firewall Premium policy and one child policy per deployed region, with example rule collection groups. A policy alone has no firewall; check current pricing."
  type        = bool
  default     = false
}

variable "link_private_dns" {
  description = "Gate 5. Private DNS zone privatelink.blob.core.windows.net and its links to each deployed hub VNet (and a spoke link for region A web)."
  type        = bool
  default     = false
}

variable "deploy_firewalls" {
  description = "Gate 6. BILLABLE. One Azure Firewall Premium per deployed region plus its public IP. Needs gates 1 and 4."
  type        = bool
  default     = false
}

variable "deploy_resolvers" {
  description = "Gate 7. BILLABLE. A DNS Private Resolver per deployed hub with an inbound and an outbound endpoint, and a forwarding ruleset to the on-premises DNS. Needs gate 1."
  type        = bool
  default     = false
}

variable "deploy_onprem_sim" {
  description = "Gate 8. Optional on-premises simulation: a VNet 10.200.0.0/16 with a DNS-server subnet and a route table. Needs no other gate."
  type        = bool
  default     = false
}

variable "deploy_vpn_sim" {
  description = "Gate 9. BILLABLE and slow. Route-based VPN gateways in hub A and in the on-premises VNet plus a VNet-to-VNet connection with BGP. Needs gates 1 and 8, and vpn_shared_key."
  type        = bool
  default     = false
}

variable "vpn_shared_key" {
  description = "Pre-shared key for the simulated tunnel. Used only with gate 9. Leave empty otherwise. Never commit a real key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "onprem_dns_ip" {
  description = "Address of the simulated on-premises DNS server that the resolver ruleset forwards corp.example.com to."
  type        = string
  default     = "10.200.10.10"
}
