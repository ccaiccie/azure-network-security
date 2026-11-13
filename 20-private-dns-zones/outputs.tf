output "resource_group" {
  description = "Resource group that holds the lab."
  value       = azurerm_resource_group.lab.name
}

output "private_zone" {
  description = "Name of the private zone."
  value       = azurerm_private_dns_zone.lab.name
}

output "vm_names" {
  description = "Names of the VMs that exist (empty when no VM gate is open)."
  value       = sort(keys(local.vms))
}

output "blob_host_name" {
  description = "Public host name of the storage account's blob endpoint (empty when gate 3 is closed)."
  value       = try(azurerm_storage_account.target[0].primary_blob_host, "")
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint (empty when gate 3 is closed)."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, "")
}

output "public_zone_name_servers" {
  description = "Name servers of the public zone (empty when gate 4 is closed). Ask one of them directly."
  value       = try(azurerm_dns_zone.public[0].name_servers, [])
}
