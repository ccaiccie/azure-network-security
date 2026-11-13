output "resource_group_name" {
  description = "Resource group of the lab (null until deploy_lab is true)."
  value       = one(azurerm_resource_group.lab[*].name)
}

output "private_ips" {
  description = "The three static private addresses."
  value = {
    vm_a   = local.app_ip
    vm_nva = local.nva_ip
    vm_b   = local.work_ip
  }
}

output "active_routes" {
  description = "Which gated routes the current variables create."
  value = {
    forward   = local.forward_route
    return    = local.return_route
    blackhole = var.enable_blackhole_route
    default   = var.enable_default_route
    tag       = var.enable_service_tag_route
    associate = local.associate
    fault     = var.fault
  }
}
