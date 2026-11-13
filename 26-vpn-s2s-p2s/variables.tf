variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource. Pick a region that has availability zones if you keep an AZ gateway SKU."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Letters and digits only, 3 to 10 characters."
  type        = string
  default     = "vpn26"

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

variable "deploy_vpn_gateway" {
  description = "Gate 1. Create the Azure VPN gateway and its public IP(s). Billable by the hour and slow: expect 30 to 45 minutes to create."
  type        = bool
  default     = false
}

variable "deploy_onprem_sim" {
  description = "Gate 2. Create the simulated on-premises VNet, vm-edge (strongSwan and FRR), vm-lan, and vm-app in the Azure VNet (billable)."
  type        = bool
  default     = false
}

variable "deploy_s2s" {
  description = "Gate 3. Create the local network gateway and the site-to-site connection. Needs gates 1 and 2."
  type        = bool
  default     = false
}

variable "deploy_p2s" {
  description = "Gate 4. Add the point-to-site configuration to the gateway. Needs gate 1. Does not add cost, but changes the gateway."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- gateway design (decide before gate 1; changing them later may rebuild the gateway)

variable "vpn_sku" {
  description = "Gateway SKU. An AZ SKU needs zone-redundant public IPs. Check current Microsoft docs for which SKUs can still be created."
  type        = string
  default     = "VpnGw1AZ"
}

variable "vpn_generation" {
  description = "Gateway generation. Generation1 is enough for VpnGw1 and VpnGw1AZ."
  type        = string
  default     = "Generation1"
}

variable "active_active" {
  description = "false: active-standby, one public IP. true: active-active, two public IPs and two tunnels from the same on-premises device."
  type        = bool
  default     = false
}

variable "azure_bgp_asn" {
  description = "Private ASN of the Azure gateway when BGP is on. Avoid the Azure-reserved ASNs; check current docs."
  type        = number
  default     = 65010
}

# ---------------------------------------------------------------- site-to-site switches (change during the activities)

variable "shared_key" {
  description = "Pre-shared key for the tunnel(s). Lab value only. It lands in Terraform state and in the VM's custom data; never reuse a real key."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.shared_key == "" || length(var.shared_key) >= 16
    error_message = "shared_key must be at least 16 characters (or empty while the S2S gate is closed)."
  }
}

variable "lng_prefixes" {
  description = "Address prefixes the local network gateway claims for the on-premises side. Break/fix 1 removes the LAN prefix."
  type        = list(string)
  default     = ["10.70.2.0/24"]
}

variable "enable_bgp" {
  description = "Run BGP over the tunnels (gateway ASN and local network gateway ASN). Activity 5 turns this on."
  type        = bool
  default     = false
}

variable "use_apipa" {
  description = "Use APIPA addresses (169.254.21.0/24 and 169.254.22.0/24) for the BGP session instead of VNet addresses. Needs enable_bgp."
  type        = bool
  default     = false
}

variable "onprem_bgp_asn" {
  description = "Private ASN of the simulated on-premises device (FRR)."
  type        = number
  default     = 65020
}

variable "onprem_bgp_ip" {
  description = "BGP address of vm-edge written in the local network gateway when use_apipa is true. Break/fix 2 changes it on purpose."
  type        = string
  default     = "169.254.21.2"
}

variable "custom_ipsec_policy" {
  description = "Apply a custom IPsec/IKE policy (AES256, SHA256, DH group 14, PFS 14) on the connection instead of the defaults. Activity 6 turns this on."
  type        = bool
  default     = false
}

variable "dpd_timeout_seconds" {
  description = "Dead peer detection timeout on the connection. The platform default is 45 seconds; check current docs for the allowed range."
  type        = number
  default     = 45
}

# ---------------------------------------------------------------- point-to-site

variable "p2s_address_pool" {
  description = "Address pool for P2S clients. It must not overlap the VNet, the on-premises side or any peered VNet."
  type        = string
  default     = "172.16.201.0/24"
}

variable "p2s_auth_type" {
  description = "certificate or entra. Entra ID authentication works with OpenVPN only."
  type        = string
  default     = "certificate"

  validation {
    condition     = contains(["certificate", "entra"], var.p2s_auth_type)
    error_message = "p2s_auth_type must be certificate or entra."
  }
}

variable "p2s_protocols" {
  description = "Tunnel protocols for certificate authentication. Valid values include OpenVPN, IkeV2 and SSTP."
  type        = list(string)
  default     = ["OpenVPN", "IkeV2"]
}

variable "p2s_root_cert_public_data" {
  description = "Base64 text of the root certificate (no BEGIN or END lines). Needed when p2s_auth_type is certificate."
  type        = string
  default     = ""
}

variable "entra_tenant_id" {
  description = "Directory (tenant) id for Entra ID authentication. Needed when p2s_auth_type is entra."
  type        = string
  default     = ""
}

variable "entra_audience" {
  description = "Application (audience) id of the Azure VPN client app registration. Check current docs for the Microsoft-registered value."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------- VMs

variable "vm_size" {
  description = "Size for the three lab VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ssh_public_key" {
  description = "Public key text (not a path) for the labadmin account. Needed when deploy_onprem_sim is true."
  type        = string
  default     = ""
}
