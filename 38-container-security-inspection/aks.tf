# Gate 2: one small AKS cluster with outbound type userDefinedRouting. The Free control plane tier is used;
# the node VM and the load balancer frontends bill by the hour. It needs the firewall and its rules,
# otherwise the nodes cannot reach the registry and the platform endpoints.

resource "azurerm_user_assigned_identity" "aks" {
  count               = var.deploy_aks ? 1 : 0
  name                = "${var.name_prefix}-aks-id"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# With userDefinedRouting the cluster identity needs rights on the subnet's VNet and on the route table.
resource "azurerm_role_assignment" "aks_vnet" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_virtual_network.spoke.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

resource "azurerm_role_assignment" "aks_route_table" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_route_table.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

resource "azurerm_kubernetes_cluster" "lab" {
  count                   = var.deploy_aks ? 1 : 0
  name                    = "${var.name_prefix}-aks"
  location                = azurerm_resource_group.lab.location
  resource_group_name     = azurerm_resource_group.lab.name
  dns_prefix              = "${var.name_prefix}-aks"
  kubernetes_version      = var.kubernetes_version
  sku_tier                = "Free"
  private_cluster_enabled = var.private_cluster
  tags                    = local.tags

  default_node_pool {
    name           = "system"
    vm_size        = var.node_vm_size
    node_count     = 1
    vnet_subnet_id = azurerm_subnet.nodes.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = var.cni_mode == "overlay" ? "overlay" : null
    network_data_plane  = var.network_policy == "cilium" ? "cilium" : "azure"
    network_policy      = var.network_policy == "none" ? null : var.network_policy
    pod_cidr            = var.cni_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting"
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_authorized_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_authorized_ranges
    }
  }

  lifecycle {
    precondition {
      condition     = var.deploy_firewall
      error_message = "deploy_aks needs deploy_firewall = true: outbound type userDefinedRouting must have a route to a firewall."
    }
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet,
    azurerm_role_assignment.aks_route_table,
    azurerm_subnet_route_table_association.nodes,
    azurerm_route.default_to_firewall,
    azurerm_firewall_policy_rule_collection_group.aks,
  ]
}
