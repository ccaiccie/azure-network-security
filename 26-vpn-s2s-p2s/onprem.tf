# Gate 2 (deploy_onprem_sim): a second VNet that plays the on-premises site.
#   vm-edge 10.70.0.10  strongSwan (IPsec) and FRR (BGP): the "VPN device". Has the public IP the local network gateway points at.
#   vm-lan  10.70.2.10  a host behind the device, with a route to Azure through vm-edge.
#   vm-app  10.60.1.10  a host in the Azure VNet, the other end of every test.
# Nothing here is a real on-premises network: the "Internet" between the two sides is Azure's own public IP space.

locals {
  onprem_on  = var.deploy_onprem_sim
  tunnels    = local.gw_count
  ike_prop   = "aes256-sha256-modp2048"
  esp_prop   = "aes256-sha256-modp2048" # PFS group 14 always on, so turning the custom policy on later does not rebuild vm-edge
  azure_pips = [for p in azurerm_public_ip.gw : p.ip_address]
}

resource "azurerm_virtual_network" "onprem" {
  count               = local.onprem_on ? 1 : 0
  name                = "${var.name_prefix}-onprem"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.70.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "edge" {
  count                = local.onprem_on ? 1 : 0
  name                 = "snet-edge"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = ["10.70.0.0/24"]
}

resource "azurerm_subnet" "lan" {
  count                = local.onprem_on ? 1 : 0
  name                 = "snet-lan"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = ["10.70.2.0/24"]
}

resource "azurerm_public_ip" "edge" {
  count               = local.onprem_on ? 1 : 0
  name                = "${var.name_prefix}-edge-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# A Standard public IP is closed to inbound traffic until an NSG allows it. IKE needs UDP 500 and 4500.
resource "azurerm_network_security_group" "edge" {
  count               = local.onprem_on ? 1 : 0
  name                = "${var.name_prefix}-edge-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "allow-ike-from-gateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = ["500", "4500"]
    source_address_prefixes    = length(local.azure_pips) > 0 ? local.azure_pips : ["192.0.2.1"]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "edge" {
  count                     = local.onprem_on ? 1 : 0
  subnet_id                 = azurerm_subnet.edge[0].id
  network_security_group_id = azurerm_network_security_group.edge[0].id
}

# The simulated LAN sends everything for Azure to vm-edge.
resource "azurerm_route_table" "lan" {
  count               = local.onprem_on ? 1 : 0
  name                = "${var.name_prefix}-lan-rt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "to-azure-via-edge"
    address_prefix         = "10.60.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.70.0.10"
  }
}

resource "azurerm_subnet_route_table_association" "lan" {
  count          = local.onprem_on ? 1 : 0
  subnet_id      = azurerm_subnet.lan[0].id
  route_table_id = azurerm_route_table.lan[0].id
}

resource "azurerm_network_interface" "edge" {
  count                 = local.onprem_on ? 1 : 0
  name                  = "vm-edge-nic"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.edge[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.70.0.10"
    public_ip_address_id          = azurerm_public_ip.edge[0].id
  }
}

resource "azurerm_network_interface" "lan" {
  count               = local.onprem_on ? 1 : 0
  name                = "vm-lan-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lan[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.70.2.10"
  }
}

resource "azurerm_network_interface" "app" {
  count               = local.onprem_on ? 1 : 0
  name                = "vm-app-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.1.10"
  }
}

locals {
  vms = local.onprem_on ? {
    "vm-edge" = azurerm_network_interface.edge[0].id
    "vm-lan"  = azurerm_network_interface.lan[0].id
    "vm-app"  = azurerm_network_interface.app[0].id
  } : {}

  # Only vm-edge gets the VPN device setup. It needs the gateway public IPs, so gate 1 should be applied first.
  edge_custom_data = local.onprem_on ? base64encode(templatefile("${path.module}/scripts/onprem-setup.sh.tftpl", {
    azure_pips = local.azure_pips
    onprem_pip = azurerm_public_ip.edge[0].ip_address
    shared_key = var.shared_key
    ike_prop   = local.ike_prop
    esp_prop   = local.esp_prop
  })) : null
}

resource "azurerm_linux_virtual_machine" "lab" {
  for_each                        = local.vms
  name                            = each.key
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [each.value]
  custom_data                     = each.key == "vm-edge" ? local.edge_custom_data : null
  tags                            = local.tags

  admin_ssh_key {
    username   = "labadmin"
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

  lifecycle {
    precondition {
      condition     = var.admin_ssh_public_key != ""
      error_message = "Set admin_ssh_public_key when deploy_onprem_sim is true."
    }
    precondition {
      condition     = var.deploy_vpn_gateway
      error_message = "Open gate 1 (deploy_vpn_gateway) before or together with gate 2: vm-edge needs the gateway public IPs."
    }
  }
}
