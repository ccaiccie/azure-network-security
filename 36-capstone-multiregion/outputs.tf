output "regions_deployed" {
  description = "Regions whose gate is open (empty when every gate is false)."
  value       = sort(keys(local.regions))
}

output "address_plan" {
  description = "The hub and spoke prefixes of the deployed regions."
  value = {
    for k, r in local.regions : k => {
      hub    = r.hub
      fw_ip  = r.fw_ip
      spokes = { for sk, s in r.spokes : sk => s.cidr }
    }
  }
}

output "firewall_private_ips" {
  description = "Private IP of each firewall (gate 6). The route tables assume the .4 address; check it."
  value       = { for k, f in azurerm_firewall.hub : k => f.ip_configuration[0].private_ip_address }
}

output "resolver_inbound_ips" {
  description = "Inbound endpoint address of each resolver (gate 7)."
  value       = { for k, i in azurerm_private_dns_resolver_inbound_endpoint.hub : k => i.ip_configurations[0].private_ip_address }
}
