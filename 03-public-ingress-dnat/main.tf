locals {
  hub_cidr      = "10.0.0.0/16"
  firewall_cidr = "10.0.1.0/26"
  bastion_cidr  = "10.0.2.0/26"
  backend_cidr  = "10.20.1.0/24"
  backend_ip    = "10.20.1.10"
  firewall_ip   = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  tags = merge(var.tags, {
    purpose    = "disposable-dnat-lab"
    managed_by = "terraform"
  })
  # Standalone route resources make deletion of the last route explicit.
  route_specs = merge(
    var.enable_default_route ? {
      default = { prefix = "0.0.0.0/0", type = "VirtualAppliance" }
    } : {},
    var.return_route_blackhole ? {
      experiment-return-blackhole = { prefix = "10.0.1.0/26", type = "None" }
    } : {}
  )
  backend_nsg_rules = {
    allow-translated-http = {
      priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp"
      source   = local.firewall_cidr, destination = "${local.backend_ip}/32", port = "8080"
    }
    allow-private-ssh = {
      priority = 110, direction = "Inbound", access = "Allow", protocol = "Tcp"
      source   = local.bastion_cidr, destination = "${local.backend_ip}/32", port = "22"
    }
    deny-platform-dns = {
      priority = 200, direction = "Outbound", access = "Deny", protocol = "*"
      source   = "*", destination = "AzurePlatformDNS", port = "*"
    }
    deny-other-inbound = {
      priority = 4000, direction = "Inbound", access = "Deny", protocol = "*"
      source   = "*", destination = "*", port = "*"
    }
    deny-other-outbound = {
      priority = 4000, direction = "Outbound", access = "Deny", protocol = "*"
      source   = "*", destination = "*", port = "*"
    }
  }
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "hub"
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
  # No customer NSG, forced tunnel, management NIC or UDR on this subnet.
}

resource "azurerm_public_ip" "firewall" {
  name                = "firewall-public-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "lab" {
  name                     = "lab-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags
  # No parent policy, DNS proxy, private-SNAT override, network or application Allow.
}

resource "azurerm_firewall_policy_rule_collection_group" "dnat" {
  count              = var.publish_dnat ? 1 : 0
  name               = "test-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200

  nat_rule_collection {
    name     = "publish-test"
    priority = 100
    action   = "Dnat"
    rule {
      name                = "operator-only"
      protocols           = ["TCP"]
      source_addresses    = [var.allowed_client_cidr]
      destination_address = azurerm_public_ip.firewall.ip_address
      destination_ports   = ["8443"]
      translated_address  = local.backend_ip
      translated_port     = "8080"
    }
  }
  # This is plain HTTP. Public port 8443 does not configure TLS.
}

resource "azurerm_firewall" "lab" {
  name                = "lab-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  tags                = local.tags
  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  depends_on = [azurerm_firewall_policy_rule_collection_group.dnat]
}

resource "azurerm_virtual_network" "backend" {
  name                = "db"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
  # Tests use literal addresses. No DNS egress is allowed from the backend.
}

resource "azurerm_subnet" "backend" {
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.backend.name
  address_prefixes                = [local.backend_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network_peering" "hub_to_db" {
  name                         = "hub-to-db"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.backend.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "db_to_hub" {
  name                         = "db-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.backend.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_db]
}

resource "azurerm_route_table" "backend" {
  name                          = "db-inspect"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  # Routes exclusively managed by azurerm_route.backend, never inline routes.
}

resource "azurerm_route" "backend" {
  for_each               = local.route_specs
  name                   = each.key
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.backend.name
  address_prefix         = each.value.prefix
  next_hop_type          = each.value.type
  next_hop_in_ip_address = each.value.type == "VirtualAppliance" ? local.firewall_ip : null
}

resource "azurerm_subnet_route_table_association" "backend" {
  subnet_id      = azurerm_subnet.backend.id
  route_table_id = azurerm_route_table.backend.id
}

resource "azurerm_network_security_group" "backend" {
  name                = "db-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.backend_nsg_rules
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.backend.id
}

resource "azurerm_network_interface" "backend" {
  name                = "db-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.backend_ip
  }
}

resource "azurerm_linux_virtual_machine" "backend" {
  name                            = "db"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.backend.id]
  tags                            = local.tags
  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }
  os_disk {
    name                 = "db-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = var.image_version
  }
  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = [
      {
        path     = "/opt/azure-dnat-lab/server.py", owner = "root:root", permissions = "0644"
        encoding = "b64", content = filebase64("${path.module}/fixtures/server.py")
      },
      {
        path     = "/etc/systemd/system/azure-dnat-fixture.service", owner = "root:root", permissions = "0644"
        encoding = "b64", content = filebase64("${path.module}/fixtures/azure-dnat-fixture.service")
      },
      {
        path     = "/usr/local/bin/dnat-ready", owner = "root:root", permissions = "0755"
        encoding = "b64", content = filebase64("${path.module}/scripts/guest-ready.sh")
      },
      {
        path    = "/etc/azure-dnat-lab.env", owner = "root:root", permissions = "0644"
        content = "BIND_IP=${local.backend_ip}\n"
      },
      {
        path    = "/etc/azure-dnat-lab.json", owner = "root:root", permissions = "0644"
        content = jsonencode({ private_ip = local.backend_ip, port = 8080, role = "backend" })
      }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "azure-dnat-fixture.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/dnat-ready > /var/log/azure-dnat-readiness.log 2>&1"]
    ]
  })]))
  boot_diagnostics {}
  depends_on = [
    azurerm_route.backend,
    azurerm_subnet_route_table_association.backend,
    azurerm_subnet_network_security_group_association.backend,
    azurerm_virtual_network_peering.db_to_hub,
    azurerm_monitor_diagnostic_setting.firewall
  ]
}
