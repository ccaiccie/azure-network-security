output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "vm_names" {
  description = "Names of the VMs that exist (empty when no VM gate is open)."
  value       = sort(keys(local.vms))
}

output "lab_blob_host" {
  description = "Blob host name of the lab storage account (empty when gate 2 is closed)."
  value       = try(azurerm_storage_account.lab[0].primary_blob_host, "")
}

output "lab_container_url" {
  description = "Anonymous container listing URL of the lab account: 200 means the firewall allowed you, 403 means it blocked you."
  value       = try("https://${azurerm_storage_account.lab[0].primary_blob_host}/labdata?restype=container&comp=list", "")
}

output "other_container_url" {
  description = "Same test URL for the second, unrelated account (empty when gate 4 is closed)."
  value       = try("https://${azurerm_storage_account.other[0].primary_blob_host}/otherdata?restype=container&comp=list", "")
}

output "blob_private_endpoint_ip" {
  description = "Private IP of the blob private endpoint (empty when gate 3 is closed)."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, "")
}

output "pls_alias" {
  description = "Alias of the Private Link Service (empty when gate 5 is closed)."
  value       = try(azurerm_private_link_service.svc[0].alias, "")
}

output "pls_endpoint_ip" {
  description = "Private IP of the consumer endpoint to the Private Link Service (empty when gate 5 is closed)."
  value       = try(azurerm_private_endpoint.pls[0].private_service_connection[0].private_ip_address, "")
}
