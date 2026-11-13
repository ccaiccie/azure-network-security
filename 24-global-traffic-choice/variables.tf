variable "subscription_id" {
  description = "Subscription that will hold the lab. Required; there is no default."
  type        = string
}

variable "location" {
  description = "Azure region for every resource (one region; the global services are not regional)."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters and digits only, 3 to 10 characters."
  type        = string
  default     = "gtc24"

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

variable "my_ip_cidr" {
  description = "Your public address as a /32, for example 203.0.113.50/32 (an example range). It is allowed to reach the lab's public entry points on port 80."
  type        = string
  default     = "203.0.113.50/32"
}

variable "admin_username" {
  description = "Linux administrator name of the two web VMs."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Text of your SSH public key (not a path). Needed only when deploy_backends is true."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of the two web VMs. Check current capacity and pricing in your region."
  type        = string
  default     = "Standard_B1s"
}

# ---------------------------------------------------------------- gates (all default to false)

variable "deploy_backends" {
  description = "Gate 1. Two small nginx VMs behind a public Standard load balancer (layer 4). Billable by the hour."
  type        = bool
  default     = false
}

variable "deploy_app_gateway" {
  description = "Gate 2. Application Gateway Standard_v2 in front of the two VMs. Needs deploy_backends. Billable by the hour."
  type        = bool
  default     = false
}

variable "deploy_front_door" {
  description = "Gate 3. Azure Front Door Standard profile with the Application Gateway as its origin. Needs deploy_app_gateway. Base fee applies; check current pricing."
  type        = bool
  default     = false
}

variable "deploy_traffic_manager" {
  description = "Gate 4. Traffic Manager profile with the Application Gateway (priority 1) and the load balancer (priority 2). Needs deploy_app_gateway."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- switches used by the activities

variable "probe_path" {
  description = "Probe path used by the load balancer, Front Door and Traffic Manager. The VMs answer 200 on /healthz only."
  type        = string
  default     = "/healthz"
}

variable "appgw_probe_path" {
  description = "Activity 6. Backend probe path of the Application Gateway. Setting it to /health (which does not exist) makes every server unhealthy."
  type        = string
  default     = "/healthz"
}

variable "tm_routing_method" {
  description = "Activity 5. Traffic Manager routing method: Priority, Weighted, Performance, Geographic, MultiValue or Subnet. The lab endpoints are set up for Priority and Weighted."
  type        = string
  default     = "Priority"

  validation {
    condition     = contains(["Priority", "Weighted", "Performance"], var.tm_routing_method)
    error_message = "The lab supports Priority, Weighted or Performance."
  }
}

variable "tm_ttl_seconds" {
  description = "Activity 5 and 6. DNS time to live of the Traffic Manager answer, in seconds."
  type        = number
  default     = 30
}

variable "tm_probe_interval_seconds" {
  description = "Traffic Manager probe interval: 30 (normal) or 10 (fast, billed extra)."
  type        = number
  default     = 30
}

variable "tm_tolerated_failures" {
  description = "Probe failures in a row that Traffic Manager tolerates before it marks an endpoint degraded."
  type        = number
  default     = 3
}

variable "appgw_only_from_front_door" {
  description = "Activity 4. true: the Application Gateway subnet accepts port 80 only from the AzureFrontDoor.Backend and AzureTrafficManager service tags, not from your address."
  type        = bool
  default     = false
}

variable "appgw_min_capacity" {
  description = "Application Gateway autoscale minimum instance count. 0 keeps the idle cost low; check current docs on cold-start behaviour."
  type        = number
  default     = 0
}

variable "appgw_max_capacity" {
  description = "Application Gateway autoscale maximum instance count."
  type        = number
  default     = 2
}
