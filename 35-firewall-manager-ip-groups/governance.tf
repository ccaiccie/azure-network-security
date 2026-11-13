# Gate 3: a custom Azure Policy definition that AUDITS Azure Firewalls that do not use the approved policy.
# Assigned at the lab resource group only, with effect audit: nothing is denied or changed. Free.
# The alias name comes from documentation knowledge: check it with the Azure Policy alias list before you rely on it.

resource "azurerm_policy_definition" "approved_fw_policy" {
  count        = var.deploy_policy_audit ? 1 : 0
  name         = "${var.name_prefix}-audit-fw-policy"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Audit Azure Firewalls that do not use an approved firewall policy"

  parameters = jsonencode({
    approvedPolicyIds = {
      type     = "Array"
      metadata = { displayName = "Approved firewall policy resource ids" }
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Network/azureFirewalls" },
        { not = { field = "Microsoft.Network/azureFirewalls/firewallPolicy.id", in = "[parameters('approvedPolicyIds')]" } }
      ]
    }
    then = { effect = "audit" }
  })
}

resource "azurerm_resource_group_policy_assignment" "approved_fw_policy" {
  count                = var.deploy_policy_audit ? 1 : 0
  name                 = "${var.name_prefix}-audit-fw"
  resource_group_id    = azurerm_resource_group.lab.id
  policy_definition_id = azurerm_policy_definition.approved_fw_policy[0].id

  parameters = jsonencode({
    approvedPolicyIds = { value = [azurerm_firewall_policy.parent.id, azurerm_firewall_policy.child_a.id, azurerm_firewall_policy.child_b.id] }
  })
}
