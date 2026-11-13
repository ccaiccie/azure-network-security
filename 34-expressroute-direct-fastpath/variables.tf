variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region. Pick one with availability zones, because the default gateway SKU is zone-redundant."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits, 3 to 10 characters."
  type        = string
  default     = "er34"

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

variable "deploy_er_gateway" {
  description = "Gate 1. Create the ExpressRoute gateway and its public IP. Billed by the hour and slow: expect 30 to 45 minutes or more."
  type        = bool
  default     = false
}

variable "deploy_circuit" {
  description = "Gate 2. Create a partner ExpressRoute circuit. It bills from creation, before the provider provisions it. Needs a provider contract."
  type        = bool
  default     = false
}

variable "deploy_connection" {
  description = "Gate 3. Connect the gateway to a circuit. Carries the FastPath setting. Needs gate 1 and a provisioned circuit."
  type        = bool
  default     = false
}

variable "deploy_direct_port" {
  description = "Gate 4. Create an ExpressRoute Direct port and a circuit on it. Needs physical fibre at the peering location. Bills hourly."
  type        = bool
  default     = false
}

variable "deploy_global_reach" {
  description = "Gate 5. Link two circuits with Global Reach. Needs two private peering ids and an unused /29."
  type        = bool
  default     = false
}

variable "deploy_test_vm" {
  description = "Gate 6. A small VM in snet-app so you can read its effective routes."
  type        = bool
  default     = false
}

variable "deploy_alerts" {
  description = "Gate 7. Action group, Log Analytics workspace, diagnostic settings and metric alerts."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- gateway and FastPath

variable "gateway_sku" {
  description = "ExpressRoute gateway SKU. ErGwScale is not covered by this lab; check the provider docs before you try it."
  type        = string
  default     = "ErGw1AZ"

  validation {
    condition     = contains(["ErGw1AZ", "ErGw2AZ", "ErGw3AZ"], var.gateway_sku)
    error_message = "gateway_sku must be ErGw1AZ, ErGw2AZ or ErGw3AZ."
  }
}

variable "enable_fastpath" {
  description = "Set FastPath (gateway bypass) on the connection. Needs an eligible gateway SKU and circuit type: check current docs."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- circuit inputs (gate 2)

variable "service_provider_name" {
  description = "Provider name exactly as listed in Azure, for example from the provider list. Placeholder only."
  type        = string
  default     = "Example Provider"
}

variable "peering_location" {
  description = "Peering location name for the partner circuit. Placeholder only."
  type        = string
  default     = "Example Location"
}

variable "circuit_bandwidth_mbps" {
  description = "Bandwidth of the partner circuit in Mbps."
  type        = number
  default     = 50
}

variable "circuit_tier" {
  description = "Circuit SKU tier: Local, Standard or Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Local", "Standard", "Premium"], var.circuit_tier)
    error_message = "circuit_tier must be Local, Standard or Premium."
  }
}

variable "circuit_family" {
  description = "MeteredData or UnlimitedData."
  type        = string
  default     = "MeteredData"
}

variable "existing_circuit_id" {
  description = "Resource id of a circuit you already own. If set, gates 2 and 4 are not needed for the connection."
  type        = string
  default     = ""
}

variable "circuit_provisioned_confirmed" {
  description = "Set true only after the provider state of the circuit is Provisioned. Gate 3 refuses to plan without it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- Direct (gate 4)

variable "direct_peering_location" {
  description = "Peering location for the Direct port. Placeholder only."
  type        = string
  default     = "Example Location"
}

variable "direct_bandwidth_gbps" {
  description = "Direct port bandwidth in Gbps: 10 or 100."
  type        = number
  default     = 10

  validation {
    condition     = contains([10, 100], var.direct_bandwidth_gbps)
    error_message = "direct_bandwidth_gbps must be 10 or 100."
  }
}

variable "direct_circuit_gbps" {
  description = "Bandwidth of the circuit created on the Direct port, in Gbps."
  type        = number
  default     = 5
}

# ---------------------------------------------------------------- Global Reach (gate 5)

variable "global_reach_peering_id" {
  description = "Private peering id of the first circuit."
  type        = string
  default     = ""
}

variable "global_reach_peer_peering_id" {
  description = "Private peering id of the second circuit."
  type        = string
  default     = ""
}

variable "global_reach_range" {
  description = "Unused /29 for the Global Reach link. RFC 5737 example; check it with scripts/er-tools.py overlap first."
  type        = string
  default     = "192.0.2.8/29"

  validation {
    condition     = can(cidrhost(var.global_reach_range, 0)) && endswith(var.global_reach_range, "/29")
    error_message = "global_reach_range must be a /29."
  }
}

# ---------------------------------------------------------------- VM and alerts

variable "admin_username" {
  description = "Admin user name of the test VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Public key text for the test VM. Not a secret."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of the test VM."
  type        = string
  default     = "Standard_B1s"
}

variable "alert_email" {
  description = "Mailbox for the alert action group."
  type        = string
  default     = "alerts@example.com"
}
