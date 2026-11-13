variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every regional resource."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits, 3 to 8 characters."
  type        = string
  default     = "ds31"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 8 lowercase letters or digits."
  }
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

variable "ipv4_vnet_prefix" {
  description = "IPv4 address space of the main VNet (RFC 1918 example)."
  type        = string
  default     = "10.31.0.0/16"
}

variable "ipv6_vnet_prefix" {
  description = "IPv6 address space of the main VNet. Default is a /48 from the documentation prefix 2001:db8::/32 (RFC 3849), so it is an example, not a routable plan. If Azure refuses it, use a ULA /48 such as fd00:db8:31::/48 (check current Microsoft docs for the allowed range sizes)."
  type        = string
  default     = "2001:db8:31::/48"
}

variable "peer_ipv4_prefix" {
  description = "IPv4 address space of the peer VNet (gate 4)."
  type        = string
  default     = "10.32.0.0/16"
}

variable "peer_ipv6_prefix" {
  description = "IPv6 address space of the peer VNet (gate 4), also from the documentation prefix."
  type        = string
  default     = "2001:db8:32::/48"
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_vms" {
  description = "Gate 1. Create vm-web-1 and vm-client-1 with dual-stack NICs (billable). Also creates the AAAA and A records in the private zone."
  type        = bool
  default     = false
}

variable "deploy_lb" {
  description = "Gate 2 (needs gate 1). Create a Standard public load balancer with an IPv4 and an IPv6 frontend in front of vm-web-1 (billable)."
  type        = bool
  default     = false
}

variable "deploy_client_ips" {
  description = "Gate 3 (needs gate 1). Give vm-client-1 its own public IPv4 and public IPv6 address, so it can test the Internet path in both families (billable)."
  type        = bool
  default     = false
}

variable "deploy_peer" {
  description = "Gate 4. Create a second dual-stack VNet and peer it with the main VNet in both directions."
  type        = bool
  default     = false
}

variable "admin_ssh_public_key" {
  description = "Text of an SSH public key for the lab VMs (gate 1). Not a path. Never put a private key here."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of the lab VMs. Check that it is available in your region and supports generation 2 images."
  type        = string
  default     = "Standard_B1s"
}

variable "break_fix" {
  description = "Break/fix selector: none | nsg_v4_only | no_aaaa | udr_v4_only."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "nsg_v4_only", "no_aaaa", "udr_v4_only"], var.break_fix)
    error_message = "break_fix must be none, nsg_v4_only, no_aaaa or udr_v4_only."
  }
}
