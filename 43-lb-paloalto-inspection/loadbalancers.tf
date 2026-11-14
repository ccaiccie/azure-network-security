# Gate 1: the public Standard load balancer (rule with floating IP, probe, outbound rule) and the internal Standard
# load balancer with an HA ports rule. Optional: a NAT Gateway for outbound.

# ---------------------------------------------------------------- public load balancer

resource "azurerm_public_ip" "plb" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "${local.p}-plb-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.use_availability_zones ? ["1", "2", "3"] : null
  tags                = local.tags
}

resource "azurerm_lb" "public" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "${local.p}-plb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "fe-web"
    public_ip_address_id = azurerm_public_ip.plb[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "untrust" {
  count           = var.deploy_firewalls ? 1 : 0
  name            = "fw-untrust"
  loadbalancer_id = azurerm_lb.public[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "untrust" {
  for_each                = local.fw_on
  network_interface_id    = azurerm_network_interface.untrust[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.untrust[0].id
}

# The probe comes from 168.63.129.16 to the untrust NIC address. The firewall answers through an interface management
# profile; the untrust NSG must allow AzureLoadBalancer; the virtual router needs a route for 168.63.129.16/32.
resource "azurerm_lb_probe" "untrust" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "probe-untrust"
  loadbalancer_id     = azurerm_lb.public[0].id
  protocol            = "Tcp"
  port                = var.probe_port
  interval_in_seconds = 5
  number_of_probes    = 2
}

# A public Standard load balancer has no HA ports rule: one rule per published port. With floating IP on, the
# destination is not rewritten, so the PAN-OS DNAT rule must match the frontend address.
resource "azurerm_lb_rule" "http" {
  count                          = var.deploy_firewalls ? 1 : 0
  name                           = "http-80"
  loadbalancer_id                = azurerm_lb.public[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-web"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.untrust[0].id]
  probe_id                       = azurerm_lb_probe.untrust[0].id
  floating_ip_enabled            = var.plb_floating_ip
  disable_outbound_snat          = true
  idle_timeout_in_minutes        = var.lb_idle_timeout_minutes
  tcp_reset_enabled              = var.lb_tcp_reset
}

# Explicit outbound rule: the firewalls' untrust NICs reach the Internet through the frontend address.
resource "azurerm_lb_outbound_rule" "egress" {
  count                    = var.deploy_firewalls ? 1 : 0
  name                     = "egress"
  loadbalancer_id          = azurerm_lb.public[0].id
  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.untrust[0].id
  allocated_outbound_ports = var.outbound_ports
  idle_timeout_in_minutes  = var.lb_idle_timeout_minutes

  frontend_ip_configuration {
    name = "fe-web"
  }
}

# ---------------------------------------------------------------- internal load balancer with HA ports

resource "azurerm_lb" "internal" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "${local.p}-ilb"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                          = "fe-trust"
    subnet_id                     = azurerm_subnet.trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ilb_frontend_ip
  }
}

resource "azurerm_lb_backend_address_pool" "trust" {
  count           = var.deploy_firewalls ? 1 : 0
  name            = "fw-trust"
  loadbalancer_id = azurerm_lb.internal[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "trust" {
  for_each                = local.fw_on
  network_interface_id    = azurerm_network_interface.trust[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.trust[0].id
}

resource "azurerm_lb_probe" "trust" {
  count               = var.deploy_firewalls ? 1 : 0
  name                = "probe-trust"
  loadbalancer_id     = azurerm_lb.internal[0].id
  protocol            = "Tcp"
  port                = var.probe_port
  interval_in_seconds = 5
  number_of_probes    = 2
}

# HA ports: protocol All and port 0 on both sides (internal Standard load balancers only). The packet's destination
# is not the frontend address, so it is passed on unchanged to the firewall.
resource "azurerm_lb_rule" "ha_ports" {
  count                          = var.deploy_firewalls ? 1 : 0
  name                           = "ha-ports"
  loadbalancer_id                = azurerm_lb.internal[0].id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "fe-trust"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.trust[0].id]
  probe_id                       = azurerm_lb_probe.trust[0].id
  floating_ip_enabled            = false
  idle_timeout_in_minutes        = var.lb_idle_timeout_minutes
  tcp_reset_enabled              = var.lb_tcp_reset
}

# ---------------------------------------------------------------- optional NAT Gateway on the untrust subnet

resource "azurerm_public_ip" "nat" {
  count               = var.deploy_firewalls && var.enable_nat_gateway ? 1 : 0
  name                = "${local.p}-nat-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "untrust" {
  count               = var.deploy_firewalls && var.enable_nat_gateway ? 1 : 0
  name                = "${local.p}-natgw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "untrust" {
  count                = var.deploy_firewalls && var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.untrust[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "untrust" {
  count          = var.deploy_firewalls && var.enable_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.untrust.id
  nat_gateway_id = azurerm_nat_gateway.untrust[0].id
}
