# Gate 3, COSTLY and SUBSCRIPTION-WIDE: the Defender for Servers plan (Plan 2), which Just-in-Time VM access needs.
# This turns the plan on for EVERY VM in the subscription and bills per server per month (check current pricing).
# The JIT policy for vm-app is NOT created here: the provider has no simple resource for it. Create it in the portal
# (Defender for Cloud, Workload protections, Just-in-time VM access), with the REST API, or with Azure Policy.
# Destroying this resource is expected to return the plan to the Free tier: confirm in the portal afterwards.

resource "azurerm_security_center_subscription_pricing" "servers" {
  count         = local.defender_on ? 1 : 0
  tier          = "Standard"
  resource_type = "VirtualMachines"
  subplan       = "P2"
}
