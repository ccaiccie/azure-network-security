variable "subscription_id" {
  description = "Azure subscription that will hold the lab."
  type        = string
}

variable "location" {
  description = "Azure region. Check current regional availability for the VM size."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the lab's own resource group (created and destroyed by this lab)."
  type        = string
  default     = "rg-routes-lab"
}

variable "admin_username" {
  description = "Admin user on the three VMs (SSH key only; the VMs have no public IP)."
  type        = string
  default     = "labadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key text for the admin user. Never put a private key here."
  type        = string
}

variable "vm_size" {
  description = "Small VM size. Check current availability and pricing."
  type        = string
  default     = "Standard_B1s"
}

variable "deploy_lab" {
  description = "Gate: create the billable resources. Setting it back to false destroys them."
  type        = bool
  default     = false
}

variable "enable_udr_forward" {
  description = "Gate: rt-app route 10.20.0.0/16 to the appliance."
  type        = bool
  default     = false
}

variable "enable_return_route" {
  description = "Gate: rt-work route 10.10.1.0/24 to the appliance."
  type        = bool
  default     = false
}

variable "enable_blackhole_route" {
  description = "Gate: rt-app route 10.20.1.0/24 with next hop None."
  type        = bool
  default     = false
}

variable "enable_default_route" {
  description = "Gate: rt-app route 0.0.0.0/0 to the appliance (forced tunnelling)."
  type        = bool
  default     = false
}

variable "enable_service_tag_route" {
  description = "Gate: rt-app route for the Storage service tag with next hop Internet."
  type        = bool
  default     = false
}

variable "bgp_route_propagation_enabled" {
  description = "Propagate gateway routes flag on both route tables. The lab has no gateway."
  type        = bool
  default     = true
}

variable "fault" {
  description = "Break/fix drill: none, forwarding_off, missing_association or return_only."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "forwarding_off", "missing_association", "return_only"], var.fault)
    error_message = "fault must be none, forwarding_off, missing_association or return_only."
  }
}
