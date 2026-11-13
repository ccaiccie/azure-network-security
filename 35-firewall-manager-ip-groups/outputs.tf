output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "parent_policy_id" {
  description = "Resource id of the parent policy."
  value       = azurerm_firewall_policy.parent.id
}

output "child_policy_ids" {
  description = "Resource ids of the child policies."
  value = {
    child_a = azurerm_firewall_policy.child_a.id
    child_b = azurerm_firewall_policy.child_b.id
  }
}

output "ip_group_ids" {
  description = "Resource ids of the IP groups."
  value = {
    spokes  = azurerm_ip_group.spokes.id
    app_a   = azurerm_ip_group.app_a.id
    app_b   = azurerm_ip_group.app_b.id
    shared  = azurerm_ip_group.shared.id
    blocked = azurerm_ip_group.blocked.id
  }
}

output "firewall_public_ip" {
  description = "Public IP of the gated firewall (empty without gate 1). Use it as dnat_public_ip."
  value       = try(azurerm_public_ip.firewall[0].ip_address, "")
}

output "firewall_private_ip" {
  description = "Private IP of the gated firewall (empty without gate 1)."
  value       = try(azurerm_firewall.lab[0].ip_configuration[0].private_ip_address, "")
}
