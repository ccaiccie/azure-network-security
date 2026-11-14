# Gate 2: two small AKS clusters with outbound type userDefinedRouting. The Free control plane tier is used; the node VMs
# and the load balancer frontends bill by the hour. The nodes can join only if the firewalls allow the AKS endpoints.

locals {
  clusters = var.deploy_aks ? {
    a = { subnet = azurerm_subnet.aks_a.id, vnet = azurerm_virtual_network.spoke_a.id, rt = azurerm_route_table.a.id, service_cidr = "172.20.0.0/16", dns_ip = "172.20.0.10" }
    b = { subnet = azurerm_subnet.aks_b.id, vnet = azurerm_virtual_network.spoke_b.id, rt = azurerm_route_table.b.id, service_cidr = "172.21.0.0/16", dns_ip = "172.21.0.10" }
  } : {}
}

resource "azurerm_user_assigned_identity" "aks" {
  for_each            = local.clusters
  name                = "${local.p}-aks-${each.key}-id"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# With userDefinedRouting the cluster identity needs rights on the subnet's VNet and on the route table.
resource "azurerm_role_assignment" "vnet" {
  for_each             = local.clusters
  scope                = each.value.vnet
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[each.key].principal_id
}

resource "azurerm_role_assignment" "rt" {
  for_each             = local.clusters
  scope                = each.value.rt
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[each.key].principal_id
}

resource "azurerm_kubernetes_cluster" "lab" {
  for_each            = local.clusters
  name                = "${local.p}-aks-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = "${local.p}-aks-${each.key}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  tags                = local.tags

  default_node_pool {
    name           = "system"
    vm_size        = var.node_vm_size
    node_count     = 1
    vnet_subnet_id = each.value.subnet
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[each.key].id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = var.cni_mode == "overlay" ? "overlay" : null
    network_data_plane  = var.network_policy == "cilium" ? "cilium" : "azure"
    network_policy      = var.network_policy == "none" ? null : var.network_policy
    pod_cidr            = var.cni_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = each.value.service_cidr
    dns_service_ip      = each.value.dns_ip
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting"
  }

  lifecycle {
    precondition {
      condition     = var.deploy_firewalls
      error_message = "deploy_aks needs deploy_firewalls = true: outbound type userDefinedRouting must have a route to a working firewall pair."
    }
  }

  depends_on = [
    azurerm_role_assignment.vnet,
    azurerm_role_assignment.rt,
    azurerm_subnet_route_table_association.a,
    azurerm_subnet_route_table_association.b,
    azurerm_route.a_default,
    azurerm_route.b_default,
    azurerm_lb_rule.ha_ports,
    azurerm_linux_virtual_machine.fw,
  ]
}
