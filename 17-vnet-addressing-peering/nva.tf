# Fix 2 for non-transitive peering: a forwarding VM in the hub plus user routes on the spokes.
# The VM is a plain Linux router, not a firewall. It only forwards.
locals {
  nva_ip = "10.0.2.4"
}

resource "azurerm_network_interface" "nva" {
  count                 = var.deploy_nva ? 1 : 0
  name                  = "nic-nva"
  location              = var.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hub_nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.nva_ip
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  count                           = var.deploy_nva ? 1 : 0
  name                            = "vm-nva"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nva[0].id]
  custom_data                     = filebase64("${path.module}/scripts/nva-cloud-init.yaml")
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
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

# Same prefix length as the peering route, so the user route wins the tie.
resource "azurerm_route_table" "spoke_a" {
  count                         = var.deploy_nva ? 1 : 0
  name                          = "rt-spoke-a"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = true
  tags                          = var.tags

  route {
    name                   = "to-spoke-b-via-nva"
    address_prefix         = local.spoke_b_space
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.nva_ip
  }
}

resource "azurerm_route_table" "spoke_b" {
  count                         = var.deploy_nva ? 1 : 0
  name                          = "rt-spoke-b"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = true
  tags                          = var.tags

  route {
    name                   = "to-spoke-a-via-nva"
    address_prefix         = local.spoke_a_space
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.nva_ip
  }
}

resource "azurerm_subnet_route_table_association" "spoke_a" {
  count          = var.deploy_nva ? 1 : 0
  subnet_id      = azurerm_subnet.spoke_a_app.id
  route_table_id = azurerm_route_table.spoke_a[0].id
}

resource "azurerm_subnet_route_table_association" "spoke_b" {
  count          = var.deploy_nva ? 1 : 0
  subnet_id      = azurerm_subnet.spoke_b_app.id
  route_table_id = azurerm_route_table.spoke_b[0].id
}
