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
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 10 characters."
  type        = string
  default     = "dns21"

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

variable "deploy_resolver" {
  description = "Gate 1. Create the DNS Private Resolver with one inbound and one outbound endpoint (billed per endpoint hour; check current pricing)."
  type        = bool
  default     = false
}

variable "deploy_ruleset" {
  description = "Gate 2. Create the forwarding ruleset, its rules and the VNet links. Needs deploy_resolver."
  type        = bool
  default     = false
}

variable "deploy_vms" {
  description = "Gate 3. Create three small Linux VMs: spoke-vm, onprem-dns (dnsmasq) and onprem-client (billable)."
  type        = bool
  default     = false
}

variable "deploy_private_endpoint" {
  description = "Gate 4. Create a storage account, a blob private endpoint, the privatelink zone and its hub link (small hourly cost)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches used by the activities

variable "link_spoke_to_ruleset" {
  description = "Activity 5. true: the spoke VNet is linked to the ruleset. false: the link is removed, so the spoke never sees the rules."
  type        = bool
  default     = true
}

variable "link_hub_to_ruleset" {
  description = "Activity 6. true: the hub VNet (which hosts both endpoints) is linked to the ruleset, so rules also apply to queries that arrive at the inbound endpoint."
  type        = bool
  default     = true
}

variable "corp_forward_target" {
  description = "Activity 5. IP address of the DNS server that the corp.example.com rule forwards to. The right value is the onprem-dns address, 10.60.1.10."
  type        = string
  default     = "10.60.1.10"
}

variable "spoke_uses_inbound_dns" {
  description = "Activity 3. true: the spoke VNet's DNS server setting is the inbound endpoint address (centralized hub DNS). false: Azure-provided DNS plus the ruleset link."
  type        = bool
  default     = false
}

variable "vm_size" {
  description = "Size of the lab VMs. Check current prices and availability in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "SSH public key (the .pub text) for the lab VMs. Needed only when deploy_vms is true. A public key is not a secret."
  type        = string
  default     = ""
}
