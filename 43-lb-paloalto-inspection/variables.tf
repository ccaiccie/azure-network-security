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
  default     = "cs43"

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

variable "deploy_firewalls" {
  description = "Gate 1. Create two VM-Series VMs, their NICs, public IPs, the public and internal load balancers and the routes (billable by the hour; needs the Marketplace terms and a licence)."
  type        = bool
  default     = false
}

variable "deploy_backends" {
  description = "Gate 2. Create two small web VMs and the web tier's internal load balancer (billable, small)."
  type        = bool
  default     = false
}

variable "deploy_gateway_lb" {
  description = "Gate 3. Create a Gateway Load Balancer, a fourth NIC on each firewall, a second public frontend chained to it. Needs gates 1 and 2. Removes the web default route while on."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Optional. Attach a NAT Gateway to the untrust subnet for outbound (billable). It normally takes precedence over the load balancer outbound rule."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- firewall image and bootstrap

variable "accept_marketplace_terms" {
  description = "When true, Terraform creates the Marketplace agreement for the plan below. This is a legal acceptance on your subscription: read the terms first, or accept them yourself with the az command in the lab guide and leave this false."
  type        = bool
  default     = false
}

variable "vmseries_publisher" {
  description = "Marketplace publisher of the VM-Series image. Check current Palo Alto Networks and Azure Marketplace documentation."
  type        = string
  default     = "paloaltonetworks"
}

variable "vmseries_offer" {
  description = "Marketplace offer. Check current documentation; offer and plan names change."
  type        = string
  default     = "vmseries-flex"
}

variable "vmseries_sku" {
  description = "Marketplace plan (SKU), for example byol or a bundle. Check current documentation."
  type        = string
  default     = "byol"
}

variable "vmseries_version" {
  description = "Image version. Pin a tested PAN-OS version for real use."
  type        = string
  default     = "latest"
}

variable "vmseries_size" {
  description = "VM size. It must support four NICs for the Gateway LB variant. Check the current Palo Alto Networks sizing guidance and Azure quotas."
  type        = string
  default     = "Standard_D3_v2"
}

variable "admin_username" {
  description = "Administrator name on the firewall and web VMs."
  type        = string
  default     = "labadmin"
}

variable "admin_password" {
  description = "Administrator password. Supply it through an environment variable (TF_VAR_admin_password) or your secret store; never commit it."
  type        = string
  default     = null
  sensitive   = true
}

variable "bootstrap_storage_account" {
  description = "Storage account that holds the bootstrap package. Empty means no bootstrap; configure by hand."
  type        = string
  default     = ""
}

variable "bootstrap_access_key" {
  description = "Access key of the bootstrap storage account. Sensitive; supply through the environment."
  type        = string
  default     = ""
  sensitive   = true
}

variable "bootstrap_file_share" {
  description = "File share that holds the bootstrap package."
  type        = string
  default     = ""
}

variable "bootstrap_share_directory" {
  description = "Directory in the share that holds config, content, license and software."
  type        = string
  default     = ""
}

variable "mgmt_source_cidr" {
  description = "Your public address as a /32. Only this source may reach the firewall management interfaces."
  type        = string

  validation {
    condition     = can(cidrhost(var.mgmt_source_cidr, 0)) && var.mgmt_source_cidr != "0.0.0.0/0"
    error_message = "mgmt_source_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "use_availability_zones" {
  description = "Place fw1 in zone 1 and fw2 in zone 2 and make the public IPs zone-redundant (needs a region with zones). When false, an availability set is used."
  type        = bool
  default     = false
}

variable "enable_accelerated_networking" {
  description = "Enable accelerated networking on the firewall data NICs. Needs a supported VM size; check current documentation."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- behaviour and break/fix switches

variable "plb_floating_ip" {
  description = "Floating IP on the public load balancer rule. The PAN-OS DNAT rule in bootstrap/ expects true. Break/fix case 3 sets it to false."
  type        = bool
  default     = true
}

variable "nsg_allow_http_inbound" {
  description = "Allow tcp/80 from the Internet in the untrust NSG. Break/fix case 4 sets it to false."
  type        = bool
  default     = true
}

variable "break_probe_block" {
  description = "Break/fix case 1. When true, a deny rule for the AzureLoadBalancer tag is added at priority 90 in the untrust NSG."
  type        = bool
  default     = false
}

variable "probe_port" {
  description = "TCP port of the health probes on the firewall data interfaces. Must not clash with a published service port."
  type        = number
  default     = 443
}

variable "outbound_ports" {
  description = "Outbound SNAT ports per backend instance on the public load balancer outbound rule. Check the current allowed values."
  type        = number
  default     = 1024
}

variable "lb_idle_timeout_minutes" {
  description = "Idle timeout of the load balancer rules in minutes. Check the current allowed range."
  type        = number
  default     = 4
}

variable "lb_tcp_reset" {
  description = "Send a TCP reset when the load balancer drops an idle flow."
  type        = bool
  default     = false
}

variable "web_vm_size" {
  description = "Size of the two small web VMs."
  type        = string
  default     = "Standard_B1s"
}

# ---------------------------------------------------------------- ranges

variable "ilb_frontend_ip" {
  description = "Static frontend address of the internal load balancer, inside snet-trust."
  type        = string
  default     = "10.80.2.10"
}

variable "web_ilb_frontend_ip" {
  description = "Static frontend address of the web tier's internal load balancer, inside snet-web."
  type        = string
  default     = "10.81.0.10"
}

variable "gwlb_frontend_ip" {
  description = "Static frontend address of the Gateway Load Balancer, inside snet-gwlb."
  type        = string
  default     = "10.80.3.10"
}
