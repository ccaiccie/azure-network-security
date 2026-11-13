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
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "snat22"

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
  description = "Gate 1. Create three small Linux VMs and their NICs (billable). Without it the lab is only free network objects."
  type        = bool
  default     = false
}

variable "deploy_nat_gateway" {
  description = "Gate 2. Create a NAT gateway with a Standard public IP (or prefix) and attach it to snet-nat (billable per hour and per GB)."
  type        = bool
  default     = false
}

variable "deploy_lb_outbound" {
  description = "Gate 3. Create an outbound-only public Standard load balancer, its public IP and an outbound rule for vm-lb (billable)."
  type        = bool
  default     = false
}

variable "deploy_firewall" {
  description = "Gate 4. Create Azure Firewall (Standard), its public IP, a policy and a route table on snet-fw (the most expensive gate)."
  type        = bool
  default     = false
}

variable "attach_vm_public_ip" {
  description = "Gate 5. Put an instance-level Standard public IP on vm-nat's NIC (needs deploy_vms). Shows NAT gateway precedence."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches changed during the activities

variable "default_outbound_access_enabled" {
  description = "Private subnet flag, inverted. true keeps default outbound access on the three VM subnets; false makes them private subnets."
  type        = bool
  default     = true
}

variable "lb_allocated_ports" {
  description = "Manual SNAT ports per instance on the load balancer outbound rule (a multiple of 8). Activity 5 lowers it to 8."
  type        = number
  default     = 1024

  validation {
    condition     = var.lb_allocated_ports % 8 == 0 && var.lb_allocated_ports >= 8
    error_message = "lb_allocated_ports must be a multiple of 8 and at least 8."
  }
}

variable "lb_idle_timeout_minutes" {
  description = "Idle timeout of the load balancer outbound rule in minutes."
  type        = number
  default     = 4
}

variable "nat_idle_timeout_minutes" {
  description = "Idle timeout of the NAT gateway in minutes (the default is 4; the maximum is 120)."
  type        = number
  default     = 4
}

variable "nat_public_ip_prefix_length" {
  description = "0 uses one public IP on the NAT gateway. 28 to 31 uses a public IP prefix instead (16 to 2 addresses)."
  type        = number
  default     = 0

  validation {
    condition     = var.nat_public_ip_prefix_length == 0 || (var.nat_public_ip_prefix_length >= 28 && var.nat_public_ip_prefix_length <= 31)
    error_message = "nat_public_ip_prefix_length must be 0 or between 28 and 31."
  }
}

variable "nat_on_fw_subnet" {
  description = "Also attach the NAT gateway to snet-fw (needs deploy_nat_gateway). Shows that the UDR to the firewall overrides it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- VMs

variable "vm_size" {
  description = "Size of the lab VMs. Check that it is available in your region."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "Public key text (not a path) for the labadmin account. Needed when deploy_vms is true."
  type        = string
  default     = ""
}
