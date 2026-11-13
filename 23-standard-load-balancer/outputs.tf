output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "frontend_ip" {
  description = "The internal frontend address that clients use."
  value       = local.frontend_ip
}

output "vm_private_ips" {
  value = merge({ for k, v in local.web_vms : k => v.ip }, { for k, v in local.client_vms : k => v.ip })
}

output "rule_settings" {
  description = "The settings of the main rule as Terraform will create them."
  value = {
    distribution = local.distribution
    floating_ip  = var.floating_ip
    probe_port   = local.probe_port
    zones        = var.frontend_zones
  }
}

output "public_ip" {
  value = var.create_public_lb ? azurerm_public_ip.regional[0].ip_address : null
}

output "global_ip" {
  value = var.create_global_lb ? azurerm_public_ip.global[0].ip_address : null
}
