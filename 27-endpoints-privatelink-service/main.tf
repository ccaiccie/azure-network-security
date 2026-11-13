# Free objects: resource group, two VNets, subnets (snet-se carries the service endpoint) and an NSG.
# Nothing in this file bills by the hour. The VNets are NOT peered on purpose: the provider and the consumer
# meet only through Private Link.

locals {
  tags = merge({ lab = "azure-27-endpoints-privatelink-service", purpose = "study" }, var.tags)

  # The policy allows the whole lab resource group, so the second account (own resource group) is outside it.
  # A resource-group scope also avoids a dependency cycle between the subnet, the policy and the account.
  sep_ids = var.deploy_se_policy && var.attach_se_policy ? [azurerm_subnet_service_endpoint_storage_policy.lab[0].id] : []
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- consumer VNet

resource "azurerm_virtual_network" "con" {
  name                = "${var.name_prefix}-vnet-con"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.50.0.0/16"]
  tags                = local.tags
}

# The service endpoint is a property of this subnet. It adds a route and changes the caller's identity.
resource "azurerm_subnet" "se" {
  name                            = "snet-se"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.con.name
  address_prefixes                = ["10.50.1.0/24"]
  service_endpoints               = ["Microsoft.Storage"]
  service_endpoint_policy_ids     = local.sep_ids
  default_outbound_access_enabled = true
}

# Private endpoints live here. Network policies decide whether the NSG below applies to endpoint traffic.
# break_fix = nsg_ignored turns the policies off, so the NSG rule is not applied. Check current Microsoft docs
# for the accepted values and for how NSG and UDR are applied to private endpoint traffic.
resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.lab.name
  virtual_network_name              = azurerm_virtual_network.con.name
  address_prefixes                  = ["10.50.2.0/24"]
  private_endpoint_network_policies = var.break_fix == "nsg_ignored" ? "Disabled" : "NetworkSecurityGroupEnabled"
}

# A client subnet with no service endpoint: it uses the public path or the private endpoint, nothing else.
resource "azurerm_subnet" "plain" {
  name                            = "snet-plain"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.con.name
  address_prefixes                = ["10.50.4.0/24"]
  default_outbound_access_enabled = true
}

resource "azurerm_network_security_group" "pe" {
  name                = "${var.name_prefix}-nsg-pe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# Optional deny rule (switch pe_nsg_deny_se): vm-se-1 must not use the endpoints.
resource "azurerm_network_security_rule" "pe_deny_se" {
  count                       = var.pe_nsg_deny_se ? 1 : 0
  name                        = "deny-snet-se-443"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.50.1.0/24"
  destination_address_prefix  = "10.50.2.0/24"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.pe.name
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

# ---------------------------------------------------------------- provider VNet (free objects only)

resource "azurerm_virtual_network" "prov" {
  name                = "${var.name_prefix}-vnet-prov"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.prov.name
  address_prefixes     = ["10.60.1.0/24"]
}

# NAT subnet of the Private Link Service. Azure reserves 5 addresses, so a /28 leaves 11 for NAT IPs.
# The service needs its network policies off on this subnet (check current provider docs for the attribute name).
resource "azurerm_subnet" "pls" {
  name                                          = "snet-pls"
  resource_group_name                           = azurerm_resource_group.lab.name
  virtual_network_name                          = azurerm_virtual_network.prov.name
  address_prefixes                              = ["10.60.2.0/28"]
  private_link_service_network_policies_enabled = false
}
