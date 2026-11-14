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
  default     = "cs42"

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
  description = "Gate 1. Create two VM-Series VMs, six NICs, public IPs, the internal load balancer and the routes (billable by the hour; needs the Marketplace terms and a licence)."
  type        = bool
  default     = false
}

variable "deploy_aks" {
  description = "Gate 2. Create two small AKS clusters with outbound type userDefinedRouting (billable). Needs deploy_firewalls."
  type        = bool
  default     = false
}

variable "enable_cheap_layer" {
  description = "Gate 3. Create NSG rules on both node subnets (free). The NetworkPolicies are manifests applied with kubectl."
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
  description = "VM size. Check the current Palo Alto Networks sizing guidance and Azure quotas."
  type        = string
  default     = "Standard_D3_v2"
}

variable "admin_username" {
  description = "Administrator name on the firewall VMs."
  type        = string
  default     = "panadmin"
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
  description = "Place fw1 in zone 1 and fw2 in zone 2 (needs a region with zones). When false, an availability set is used."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- behaviour switches

variable "cni_mode" {
  description = "node_subnet (pods take VNet addresses) or overlay (pod CIDR, node SNAT). Changing it replaces the clusters."
  type        = string
  default     = "node_subnet"

  validation {
    condition     = contains(["node_subnet", "overlay"], var.cni_mode)
    error_message = "cni_mode must be node_subnet or overlay."
  }
}

variable "network_policy" {
  description = "none, azure, calico or cilium. Check current AKS documentation for supported combinations and retirements."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["none", "azure", "calico", "cilium"], var.network_policy)
    error_message = "network_policy must be none, azure, calico or cilium."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version, or null for the current default."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Node VM size for the single system node of each cluster."
  type        = string
  default     = "Standard_B2s"
}

variable "b_reply_next_hop_override" {
  description = "Break/fix switch. When set to a firewall trust address such as 10.70.2.5, cluster B's route for 10.71.0.0/16 names that address instead of the ILB. Leave empty."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------- ranges

variable "ilb_frontend_ip" {
  description = "Static frontend address of the internal load balancer, inside snet-trust."
  type        = string
  default     = "10.70.2.10"
}

variable "pod_cidr" {
  description = "Overlay pod CIDR (only used when cni_mode is overlay)."
  type        = string
  default     = "10.244.0.0/16"
}
