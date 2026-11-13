# Gate 3 (deploy_branch_sim): a VNet that plays a branch office.
#   vm-edge 10.80.0.10  strongSwan (IPsec) and FRR (BGP, ASN 65020): the "branch VPN device". Has the public IP the VPN site points at.
#   vm-lan  10.80.2.10  a host behind the device, with a route to Azure prefixes through vm-edge.
# The "Internet" between the branch and the hub is Azure's own public IP space. Nothing here is a real on-premises network.

locals {
  branch_on = var.deploy_branch_sim
  vpn_on    = var.deploy_vpn && var.deploy_hub1 && var.deploy_branch_sim
  # Public tunnel addresses of the two hub VPN gateway instances and their BGP addresses. Attribute names: check provider docs.
  gw_tunnel_ips = local.vpn_on ? [
    azurerm_vpn_gateway.hub1[0].bgp_settings[0].instance_0_bgp_peering_address[0].tunnel_ips[0],
    azurerm_vpn_gateway.hub1[0].bgp_settings[0].instance_1_bgp_peering_address[0].tunnel_ips[0],
  ] : ["203.0.113.30", "203.0.113.31"]
  gw_bgp_ips = local.vpn_on ? [
    azurerm_vpn_gateway.hub1[0].bgp_settings[0].instance_0_bgp_peering_address[0].default_ips[0],
    azurerm_vpn_gateway.hub1[0].bgp_settings[0].instance_1_bgp_peering_address[0].default_ips[0],
  ] : ["10.100.0.12", "10.100.0.13"]
}

resource "azurerm_virtual_network" "branch" {
  count               = local.branch_on ? 1 : 0
  name                = "${var.name_prefix}-branch"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.80.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "edge" {
  count                = local.branch_on ? 1 : 0
  name                 = "snet-edge"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.branch[0].name
  address_prefixes     = ["10.80.0.0/24"]
}

resource "azurerm_subnet" "lan" {
  count                = local.branch_on ? 1 : 0
  name                 = "snet-lan"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.branch[0].name
  address_prefixes     = ["10.80.2.0/24"]
}

resource "azurerm_public_ip" "edge" {
  count               = local.branch_on ? 1 : 0
  name                = "${var.name_prefix}-edge-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# A Standard public IP is closed to inbound traffic until an NSG allows it: IKE needs UDP 500 and 4500.
resource "azurerm_network_security_group" "edge" {
  count               = local.branch_on ? 1 : 0
  name                = "${var.name_prefix}-edge-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-ike"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = ["500", "4500"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "edge" {
  count                 = local.branch_on ? 1 : 0
  name                  = "vm-edge-nic"
  location              = var.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.edge[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.80.0.10"
    public_ip_address_id          = azurerm_public_ip.edge[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "edge" {
  count                     = local.branch_on ? 1 : 0
  network_interface_id      = azurerm_network_interface.edge[0].id
  network_security_group_id = azurerm_network_security_group.edge[0].id
}

resource "azurerm_network_interface" "lan" {
  count               = local.branch_on ? 1 : 0
  name                = "vm-lan-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lan[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.80.2.10"
  }
}

# vm-lan sends every Azure prefix (the whole 10.0.0.0/8 except the local /16) to the device.
resource "azurerm_route_table" "lan" {
  count               = local.branch_on ? 1 : 0
  name                = "${var.name_prefix}-lan-rt"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "azure-via-edge"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.80.0.10"
  }
}

resource "azurerm_subnet_route_table_association" "lan" {
  count          = local.branch_on ? 1 : 0
  subnet_id      = azurerm_subnet.lan[0].id
  route_table_id = azurerm_route_table.lan[0].id
}

resource "azurerm_linux_virtual_machine" "edge" {
  count                           = local.branch_on ? 1 : 0
  name                            = "vm-edge"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.edge[0].id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/onprem-setup.sh.tftpl", {
    psk          = var.shared_key
    gw_ips       = local.gw_tunnel_ips
    gw_bgp_ips   = local.gw_bgp_ips
    local_public = azurerm_public_ip.edge[0].ip_address
    local_asn    = 65020
    hub_asn      = 65515
  }))

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key before opening gate 3."
    }
  }
}

resource "azurerm_linux_virtual_machine" "lan" {
  count                           = local.branch_on ? 1 : 0
  name                            = "vm-lan"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lan[0].id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
