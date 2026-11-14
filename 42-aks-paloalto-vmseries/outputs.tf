output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "ilb_frontend_ip" {
  value = var.ilb_frontend_ip
}

output "firewall_mgmt_public_ips" {
  description = "Management public IPs; reachable only from mgmt_source_cidr."
  value       = { for k, v in azurerm_public_ip.mgmt : k => v.ip_address }
}

output "firewall_untrust_public_ips" {
  description = "Public IPs that PAN-OS source NAT uses for Internet egress."
  value       = { for k, v in azurerm_public_ip.untrust : k => v.ip_address }
}

output "aks_credentials_commands" {
  value = { for k, v in azurerm_kubernetes_cluster.lab : k => "az aks get-credentials -g ${azurerm_resource_group.lab.name} -n ${v.name} --context aks-${k} --overwrite-existing" }
}
