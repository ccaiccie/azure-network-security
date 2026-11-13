variable "subscription_id" {
  description = "The Azure subscription ID you have decided to use. No default on purpose."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "ermr"
}

variable "location_a" {
  description = "Azure region of hub A (an example; choose your own)."
  type        = string
  default     = "westeurope"
}

variable "location_b" {
  description = "Azure region of hub B (an example; choose your own)."
  type        = string
  default     = "northeurope"
}

# ---- Gates: every one defaults to false -------------------------------------

variable "deploy_lab" {
  description = "Create the resource group, hubs, spokes, GatewaySubnets and hub-to-spoke peerings."
  type        = bool
  default     = false
}

variable "deploy_er_gateways" {
  description = "Create one ExpressRoute gateway per hub. Billable by the hour; slow to deploy."
  type        = bool
  default     = false
}

variable "deploy_test_vms" {
  description = "Create one small VM per spoke (no public IP) so that effective routes have a NIC to show."
  type        = bool
  default     = false
}

variable "create_circuits" {
  description = "Create two ExpressRoute circuit resources. They bill from creation and need a connectivity provider."
  type        = bool
  default     = false
}

variable "configure_private_peering" {
  description = "Create private peering on the circuits this module owns. Only after the provider has provisioned them."
  type        = bool
  default     = false
}

variable "create_connections" {
  description = "Create the four gateway connections (each hub to each circuit)."
  type        = bool
  default     = false
}

variable "enable_diagnostics" {
  description = "Create a Log Analytics workspace and send circuit and gateway metrics to it."
  type        = bool
  default     = false
}

# ---- Design inputs ------------------------------------------------------------

variable "er_gateway_sku" {
  description = "ExpressRoute gateway SKU. A zone-redundant (AZ) SKU is assumed; check which SKUs you can still create."
  type        = string
  default     = "ErGw1AZ"
}

variable "public_ip_zones" {
  description = "Zones for the gateway public IPs. Use an empty list in a region without availability zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "customer_asn" {
  description = "Your private ASN (example 65001). Azure reserves 65515 to 65520."
  type        = number
  default     = 65001

  validation {
    condition     = (var.customer_asn >= 64512 && var.customer_asn <= 65514) || (var.customer_asn >= 65521 && var.customer_asn <= 65534)
    error_message = "Use a private 16-bit ASN outside the range Azure reserves (confirm the range in the current docs)."
  }
}

variable "circuits" {
  description = "The two circuits, keyed a and b. All values are placeholders: take real ones from your provider."
  type = map(object({
    service_provider_name         = string
    peering_location              = string
    bandwidth_in_mbps             = number
    primary_peer_address_prefix   = string
    secondary_peer_address_prefix = string
    vlan_id                       = number
  }))
  default = {
    a = {
      service_provider_name         = "REPLACE-PROVIDER-1"
      peering_location              = "REPLACE-LOCATION-1"
      bandwidth_in_mbps             = 50
      primary_peer_address_prefix   = "172.31.255.0/30"
      secondary_peer_address_prefix = "172.31.255.4/30"
      vlan_id                       = 100
    }
    b = {
      service_provider_name         = "REPLACE-PROVIDER-2"
      peering_location              = "REPLACE-LOCATION-2"
      bandwidth_in_mbps             = 50
      primary_peer_address_prefix   = "172.31.255.8/30"
      secondary_peer_address_prefix = "172.31.255.12/30"
      vlan_id                       = 200
    }
  }
}

variable "circuit_sku_tier" {
  description = "Circuit SKU tier: Standard, Premium or Local (check which fit your regions)."
  type        = string
  default     = "Standard"
}

variable "circuit_sku_family" {
  description = "MeteredData or UnlimitedData."
  type        = string
  default     = "MeteredData"
}

variable "existing_circuit_ids" {
  description = "IDs of circuits you did not create with this module (keys a and b). Used when create_circuits is false."
  type        = map(string)
  default     = {}
}

variable "connection_weights" {
  description = "Connection weight per connection, keyed hub-circuit: a-a, a-b, b-a, b-b. Higher wins for Azure to on-premises."
  type        = map(number)
  default = {
    "a-a" = 100
    "a-b" = 0
    "b-b" = 100
    "b-a" = 0
  }

  validation {
    condition     = alltrue([for k in ["a-a", "a-b", "b-a", "b-b"] : contains(keys(var.connection_weights), k)])
    error_message = "connection_weights needs all four keys: a-a, a-b, b-a, b-b."
  }
}

variable "authorization_keys" {
  description = "Authorization keys for circuits owned in another subscription, keyed like connection_weights. Never commit these."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "peering_shared_key" {
  description = "Optional BGP MD5 shared key for private peering. Leave null unless your provider requires it."
  type        = string
  default     = null
  sensitive   = true
}

variable "admin_username" {
  description = "Admin user for the test VMs."
  type        = string
  default     = "labadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the test VMs. Required when deploy_test_vms is true."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of the test VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace."
  type        = number
  default     = 30
}
