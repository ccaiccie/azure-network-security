output "resource_group_name" {
  value = try(module.lab[0].resource_group_name, null)
}
output "location" {
  value = try(module.lab[0].location, null)
}
output "route_server_id" {
  value = try(module.lab[0].route_server_id, null)
}
output "route_server_name" {
  value = try(module.lab[0].route_server_name, null)
}
output "route_server_peer_ips" {
  value = try(module.lab[0].route_server_peer_ips, null)
}
output "route_server_asn" {
  value = try(module.lab[0].route_server_asn, null)
}
output "route_server_routing_state" {
  value = try(module.lab[0].route_server_routing_state, null)
}
output "app_vm_id" {
  value = try(module.lab[0].app_vm_id, null)
}
output "remote_vm_id" {
  value = try(module.lab[0].remote_vm_id, null)
}
output "nva_vm_ids" {
  value = try(module.lab[0].nva_vm_ids, null)
}
output "nic_ids" {
  value = try(module.lab[0].nic_ids, null)
}
output "private_ips" {
  value = try(module.lab[0].private_ips, null)
}
output "destination_ip" {
  value = try(module.lab[0].destination_ip, null)
}
output "destination_prefix" {
  value = try(module.lab[0].destination_prefix, null)
}
output "bastion_name" {
  value = try(module.lab[0].bastion_name, null)
}
output "admin_username" {
  value = try(module.lab[0].admin_username, null)
}
output "image_id" {
  value = try(module.lab[0].image_id, null)
}
output "frr_version" {
  value = try(module.lab[0].frr_version, null)
}
output "deployment_enabled" {
  value = var.deploy_lab
}
