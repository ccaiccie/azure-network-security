# Gate 1: one small AKS cluster. The control plane uses the Free tier; the node VM, the managed
# Standard Load Balancer and its public IP bill by the hour. Gates 3 and 4 extend this cluster.

resource "azurerm_user_assigned_identity" "aks" {
  count               = var.deploy_aks ? 1 : 0
  name                = "${var.name_prefix}-aks-id"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# The cluster identity needs rights on the BYO VNet to create load balancer frontends and join nodes.
resource "azurerm_role_assignment" "aks_network" {
  count                = var.deploy_aks ? 1 : 0
  scope                = azurerm_virtual_network.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

# Used only when outbound_type = userAssignedNATGateway. It must be attached to the node subnet
# before the cluster is created, which depends_on below guarantees.
resource "azurerm_public_ip" "nat" {
  count               = var.deploy_aks && var.outbound_type == "userAssignedNATGateway" ? 1 : 0
  name                = "${var.name_prefix}-nat-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "lab" {
  count               = var.deploy_aks && var.outbound_type == "userAssignedNATGateway" ? 1 : 0
  name                = "${var.name_prefix}-natgw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "lab" {
  count                = var.deploy_aks && var.outbound_type == "userAssignedNATGateway" ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.lab[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  count          = var.deploy_aks && var.outbound_type == "userAssignedNATGateway" ? 1 : 0
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.lab[0].id
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
    max_pods       = var.max_pods
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = var.cni_mode == "overlay" ? "overlay" : null
    network_data_plane  = var.enable_cilium ? "cilium" : "azure"
    network_policy      = var.enable_cilium ? "cilium" : null
    pod_cidr            = var.cni_mode == "overlay" ? var.pod_cidr : null
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = var.outbound_type
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_authorized_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_authorized_ranges
    }
  }

  # Gate 3. dns_zone_ids is required by the provider block; an empty list keeps the lab free of DNS integration.
  dynamic "web_app_routing" {
    for_each = var.enable_app_routing ? [1] : []
    content {
      dns_zone_ids = []
    }
  }

  depends_on = [
    azurerm_role_assignment.aks_network,
    azurerm_subnet_nat_gateway_association.nodes,
  ]
}

# Gate 4: a user pool in a second subnet of the same VNet.
resource "azurerm_kubernetes_cluster_node_pool" "second" {
  count                 = var.deploy_aks && var.add_second_pool ? 1 : 0
  name                  = "user2"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.lab[0].id
  vm_size               = var.node_vm_size
  node_count            = 1
  vnet_subnet_id        = azurerm_subnet.nodes2.id
  max_pods              = var.max_pods
  tags                  = local.tags
}
