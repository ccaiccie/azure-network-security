locals {
  # Fixed teaching address plan. The firewall private IP is NOT hardcoded.
  hub_cidr      = "10.10.0.0/16"
  firewall_cidr = "10.10.0.0/26"
  bastion_cidr  = "10.10.1.0/26"
  spoke_cidr    = "10.20.0.0/16"
  workload_cidr = "10.20.1.0/24"
  vm_private_ip = "10.20.1.4"
  firewall_ip   = azurerm_firewall.egress.ip_configuration[0].private_ip_address
  allowed_fqdns = sort(tolist(var.allowed_fqdns))
  tags = merge(var.tags, {
    purpose    = "disposable-egress-lab"
    managed_by = "terraform"
  })
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [local.hub_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.firewall_cidr]
  # No NSG or default-to-self UDR belongs on this managed firewall subnet.
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-egress"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "egress" {
  name                     = "policy-egress"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags

  dns {
    proxy_enabled = true
    # No custom upstream: use Azure-provided resolution.
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "egress" {
  name               = "rcg-egress-demo"
  firewall_policy_id = azurerm_firewall_policy.egress.id
  priority           = 300

  dynamic "network_rule_collection" {
    for_each = var.policy_mode == "network" ? [1] : []
    content {
      name     = "allow-selected-tcp443"
      priority = 300
      action   = "Allow"

      rule {
        name              = "allow-demo-tcp443"
        description       = "DNS-derived destination IPs on TCP443, not HTTP Host or SNI enforcement."
        protocols         = ["TCP"]
        source_addresses  = [local.workload_cidr]
        destination_fqdns = local.allowed_fqdns
        destination_ports = ["443"]
      }
    }
  }

  dynamic "application_rule_collection" {
    for_each = var.policy_mode == "application" ? [1] : []
    content {
      name     = "allow-selected-https"
      priority = 300
      action   = "Allow"

      rule {
        name              = "allow-demo-https"
        description       = "Separate application proxy scenario; Standard does not decrypt URL paths."
        source_addresses  = [local.workload_cidr]
        destination_fqdns = local.allowed_fqdns

        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }
  # No catch-all network deny: it would preempt application rules.
  # All other unmatched traffic reaches the firewall's implicit deny.
}

resource "azurerm_firewall" "egress" {
  name                = "fw-egress"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.egress.id
  tags                = local.tags

  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.egress]
}

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [local.spoke_cidr]
  dns_servers         = [local.firewall_ip]
  tags                = local.tags
}

resource "azurerm_subnet" "workload" {
  name                            = "snet-workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke.name
  address_prefixes                = [local.workload_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  # Serialize the two peering operations to avoid concurrent peering changes.
  depends_on = [azurerm_virtual_network_peering.hub_to_spoke]
}

resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-egress"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.firewall_ip
  }
}

resource "azurerm_subnet_route_table_association" "workload" {
  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bastion_cidr
    destination_address_prefix = local.vm_private_ip
  }

  security_rule {
    name                       = "deny-other-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = { Udp = 100, Tcp = 101 }
    content {
      name                       = "allow-dns-proxy-${lower(security_rule.key)}"
      priority                   = security_rule.value
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = security_rule.key
      source_port_range          = "*"
      destination_port_range     = "53"
      source_address_prefix      = local.workload_cidr
      destination_address_prefix = "${local.firewall_ip}/32"
    }
  }

  security_rule {
    name                       = "deny-direct-platform-dns"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzurePlatformDNS"
  }

  security_rule {
    name                       = "allow-http-https-to-firewall-policy"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = local.workload_cidr
    destination_address_prefix = "Internet"
    # Original destination is still the remote server, NOT the firewall next hop.
    # TCP80 is allowed here only so a negative test reaches the firewall.
  }

  security_rule {
    name                       = "deny-other-outbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_network_interface" "workload" {
  name                = "nic-egress"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  # Inherit spoke VNet DNS. No NIC override, public IP, or IP forwarding.

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.vm_private_ip
  }
}

resource "azurerm_linux_virtual_machine" "workload" {
  name                            = "vm-egress"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.workload.id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }

  os_disk {
    name                 = "disk-vm-egress-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = var.image_version
  }

  # Write the test harness without fetching packages or starting network tests.
  custom_data = base64encode("#cloud-config\n${yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = [
      {
        path        = "/usr/local/bin/egress-demo"
        permissions = "0755"
        owner       = "root:root"
        encoding    = "b64"
        content     = filebase64("${path.module}/scripts/guest-tests.sh")
      },
      {
        path        = "/etc/egress-demo.json"
        permissions = "0644"
        owner       = "root:root"
        content = jsonencode({
          firewall_private_ip = local.firewall_ip
          firewall_public_ip  = azurerm_public_ip.firewall.ip_address
          vm_private_ip       = local.vm_private_ip
          policy_mode         = var.policy_mode
          allowed_fqdns       = local.allowed_fqdns
        })
      }
    ]
  })}")

  boot_diagnostics {}

  depends_on = [
    azurerm_subnet_route_table_association.workload,
    azurerm_subnet_network_security_group_association.workload,
    azurerm_virtual_network_peering.spoke_to_hub,
    azurerm_monitor_diagnostic_setting.firewall
  ]
}
