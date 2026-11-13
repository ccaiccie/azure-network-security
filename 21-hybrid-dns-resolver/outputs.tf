output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "inbound_endpoint_ip" {
  description = "Address of the inbound endpoint (the forward target for on-premises DNS)."
  value       = local.inbound_ip
}

output "storage_account_fqdn" {
  description = "Blob FQDN of the storage account (empty when deploy_private_endpoint is false)."
  value       = try("${azurerm_storage_account.target[0].name}.blob.core.windows.net", "")
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint (empty when deploy_private_endpoint is false)."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, "")
}
