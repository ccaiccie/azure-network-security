output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "firewall_private_ip" {
  description = "Private IP of the firewall; the default route's next hop (empty when deploy_firewall is false)."
  value       = try(azurerm_firewall.lab[0].ip_configuration[0].private_ip_address, "")
}

output "firewall_public_ip" {
  description = "Public IP of the firewall; the DNAT address (empty when deploy_firewall is false)."
  value       = try(azurerm_public_ip.fw[0].ip_address, "")
}

output "aks_name" {
  description = "Name of the AKS cluster (empty when deploy_aks is false)."
  value       = try(azurerm_kubernetes_cluster.lab[0].name, "")
}

output "node_resource_group" {
  description = "Node resource group (MC_...) that AKS creates (empty when deploy_aks is false)."
  value       = try(azurerm_kubernetes_cluster.lab[0].node_resource_group, "")
}

output "workspace_id" {
  description = "Log Analytics workspace (customer) ID for az monitor log-analytics query (empty when enable_diagnostics is false)."
  value       = try(azurerm_log_analytics_workspace.lab[0].workspace_id, "")
}

output "get_credentials_command" {
  description = "Command that writes the kubeconfig context (empty when deploy_aks is false)."
  value       = var.deploy_aks ? "az aks get-credentials -g ${azurerm_resource_group.lab.name} -n ${var.name_prefix}-aks --overwrite-existing" : ""
}
