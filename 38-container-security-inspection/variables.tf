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
  default     = "cs38"

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

variable "deploy_firewall" {
  description = "Gate 1. Create the Azure Firewall, its policy, two public IPs and the two routes (billable by the hour). Without it the lab is only free network objects."
  type        = bool
  default     = false
}

variable "deploy_aks" {
  description = "Gate 2. Create one small AKS cluster with outbound type userDefinedRouting (billable). Needs deploy_firewall."
  type        = bool
  default     = false
}

variable "enable_dnat" {
  description = "Gate 3. Add a DNAT rule from the firewall public IP, tcp/80, to ingress_ilb_ip. Needs deploy_firewall."
  type        = bool
  default     = false
}

variable "enable_diagnostics" {
  description = "Gate 4. Create a Log Analytics workspace and send the firewall logs to it (billed per GB ingested). Needs deploy_firewall."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- behaviour switches (not gates)

variable "cni_mode" {
  description = "overlay = Azure CNI Overlay (pods use pod_cidr, the firewall sees the node IP). node_subnet = Azure CNI node subnet (pods use real node subnet addresses, the firewall sees the pod IP). Changing it replaces the cluster."
  type        = string
  default     = "overlay"

  validation {
    condition     = contains(["overlay", "node_subnet"], var.cni_mode)
    error_message = "cni_mode must be overlay or node_subnet."
  }
}

variable "network_policy" {
  description = "Policy engine: none, azure, calico or cilium (cilium also switches the dataplane and needs overlay in this lab). Changing it replaces the cluster. Check current docs for engine status."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["none", "azure", "calico", "cilium"], var.network_policy)
    error_message = "network_policy must be none, azure, calico or cilium."
  }
}

variable "firewall_sku" {
  description = "Firewall tier and policy tier: Basic (smallest), Standard or Premium. Check the feature comparison in current docs; Basic has limits."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku)
    error_message = "firewall_sku must be Basic, Standard or Premium."
  }
}

variable "include_fqdn_tag_rule" {
  description = "Create the application rule with the AzureKubernetesService FQDN tag. false reproduces break/fix case 1 (nodes cannot join) when applied before the cluster."
  type        = bool
  default     = true
}

variable "egress_rule_source" {
  description = "Source range of the test application rule. 10.61.1.0/24 (node subnet) works on overlay. Set 10.244.0.0/16 to reproduce break/fix case 2."
  type        = string
  default     = "10.61.1.0/24"
}

variable "egress_test_fqdn" {
  description = "Domain that the test application rule allows."
  type        = string
  default     = "example.com"
}

variable "add_legacy_network_rules" {
  description = "Add network rules that older AKS egress documents listed (tunnel to the control plane). Usually not needed on current clusters; check current docs."
  type        = bool
  default     = false
}

variable "ingress_ilb_ip" {
  description = "Fixed private address of the internal load balancer in snet-nodes. The DNAT rule translates to it and manifests/svc-ilb.yaml requests it."
  type        = string
  default     = "10.61.1.100"
}

variable "bypass_client_cidr" {
  description = "Optional /32 of your own public IP. Adds a route with next hop Internet so replies to it skip the firewall (Activity 6). Empty adds nothing. Never use the documentation example."
  type        = string
  default     = ""
}

variable "private_cluster" {
  description = "Make the API server private (private endpoint and private DNS zone). You then need a path into the VNet for kubectl. Changing it replaces the cluster."
  type        = bool
  default     = false
}

variable "api_authorized_ranges" {
  description = "Public source ranges allowed to reach the API server. Empty means open. Use your own public IP as a /32."
  type        = list(string)
  default     = []
}

variable "node_subnet_cidr" {
  description = "Node subnet prefix inside 10.61.0.0/16."
  type        = string
  default     = "10.61.1.0/24"
}

variable "pod_cidr" {
  description = "Pod CIDR for overlay. Must not overlap any range the pods must reach."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR. Must not overlap the VNets or the pod CIDR. Fixed at cluster creation."
  type        = string
  default     = "172.20.0.0/16"
}

variable "dns_service_ip" {
  description = "Address of CoreDNS inside the service CIDR; not the first address."
  type        = string
  default     = "172.20.0.10"
}

variable "node_vm_size" {
  description = "Smallest practical VM size for the node pool. Check regional availability and quota."
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  description = "Kubernetes version. null uses the AKS default for the region."
  type        = string
  default     = null
}
