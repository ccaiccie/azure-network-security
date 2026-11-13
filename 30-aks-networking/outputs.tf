output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "aks_vnet_name" {
  description = "Name of the AKS VNet."
  value       = azurerm_virtual_network.aks.name
}

output "aks_name" {
  description = "Name of the AKS cluster (empty when deploy_aks is false)."
  value       = try(azurerm_kubernetes_cluster.lab[0].name, "")
}

output "node_resource_group" {
  description = "Node resource group (MC_...) that AKS creates (empty when deploy_aks is false)."
  value       = try(azurerm_kubernetes_cluster.lab[0].node_resource_group, "")
}

output "onprem_vm_private_ip" {
  description = "Private IP of the stand-in VM (empty when deploy_onprem_vm is false)."
  value       = try(azurerm_network_interface.onprem[0].private_ip_address, "")
}

output "get_credentials_command" {
  description = "Command that writes the kubeconfig context (empty when deploy_aks is false)."
  value       = var.deploy_aks ? "az aks get-credentials -g ${azurerm_resource_group.lab.name} -n ${var.name_prefix}-aks --overwrite-existing" : ""
}
