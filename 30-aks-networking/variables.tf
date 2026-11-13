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
  default     = "aks30"

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

variable "deploy_aks" {
  description = "Gate 1. Create one small AKS cluster (billable: node VM, load balancer, public IP). Without it the lab is only free network objects."
  type        = bool
  default     = false
}

variable "deploy_onprem_vm" {
  description = "Gate 2. Create the on-premises stand-in VM with a listener on tcp/8080 (billable)."
  type        = bool
  default     = false
}

variable "enable_app_routing" {
  description = "Gate 3. Turn on the application routing add-on (managed NGINX ingress). Needs deploy_aks. Adds a load balancer frontend and a public IP."
  type        = bool
  default     = false
}

variable "add_second_pool" {
  description = "Gate 4. Add a node pool in snet-nodes2 (billable VM). Needs deploy_aks."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- behaviour switches (not gates)

variable "cni_mode" {
  description = "overlay = Azure CNI Overlay (pods use pod_cidr). node_subnet = Azure CNI node subnet (pods use real node subnet addresses). Changing it replaces the cluster."
  type        = string
  default     = "overlay"

  validation {
    condition     = contains(["overlay", "node_subnet"], var.cni_mode)
    error_message = "cni_mode must be overlay or node_subnet."
  }
}

variable "enable_cilium" {
  description = "Use the Cilium dataplane (Azure CNI Powered by Cilium). Needs overlay here. Changing it replaces the cluster. Check current docs for versions and regions."
  type        = bool
  default     = false
}

variable "outbound_type" {
  description = "loadBalancer (default) or userAssignedNATGateway (the lab then creates a NAT gateway and attaches it to the node subnet; it bills). Changing it replaces the cluster."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer or userAssignedNATGateway."
  }
}

variable "private_cluster" {
  description = "Make the API server private (private endpoint and private DNS zone). You then need a path into the VNet for kubectl. Changing it replaces the cluster."
  type        = bool
  default     = false
}

variable "api_authorized_ranges" {
  description = "Public source ranges allowed to reach the API server. Empty means open. Use your own public IP as a /32; never the documentation example."
  type        = list(string)
  default     = []
}

variable "link_private_zone" {
  description = "Link the private DNS zone lab30.internal to the AKS VNet. false reproduces break/fix case 4 (NXDOMAIN in pods)."
  type        = bool
  default     = false
}

variable "onprem_allowed_source" {
  description = "Source range that the stand-in NSG allows to tcp/8080. 10.40.1.0/24 (node subnet) works for overlay. Set 10.244.0.0/16 to reproduce break/fix case 1."
  type        = string
  default     = "10.40.1.0/24"
}

variable "node_subnet_cidr" {
  description = "Node subnet prefix inside 10.40.0.0/16. Shrink it (for example a /26) with cni_mode = node_subnet to see subnet exhaustion."
  type        = string
  default     = "10.40.1.0/24"
}

variable "pod_cidr" {
  description = "Pod CIDR for overlay. Must not overlap any range the pods must reach."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR. Must not overlap the VNet, peered or on-premises ranges or the pod CIDR. Fixed at cluster creation."
  type        = string
  default     = "172.20.0.0/16"
}

variable "dns_service_ip" {
  description = "Address of CoreDNS inside the service CIDR; not the first address."
  type        = string
  default     = "172.20.0.10"
}

variable "max_pods" {
  description = "Maximum pods per node. null uses the AKS default for the model (check current docs)."
  type        = number
  default     = null
}

variable "node_vm_size" {
  description = "Smallest practical VM size for the node pools. Check regional availability and quota."
  type        = string
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  description = "Kubernetes version. null uses the AKS default for the region."
  type        = string
  default     = null
}

variable "admin_ssh_public_key" {
  description = "Public key text (not a path) for the stand-in VM. Required when deploy_onprem_vm is true."
  type        = string
  default     = ""
}
