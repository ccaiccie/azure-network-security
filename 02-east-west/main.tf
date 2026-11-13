locals {
  hub_cidr      = "10.0.0.0/16"
  firewall_cidr = "10.0.1.0/26"
  bastion_cidr  = "10.0.2.0/26"
  firewall_ip   = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  tags = merge(var.tags, {
    purpose    = "disposable-east-west-lab"
    managed_by = "terraform"
  })
  spokes = {
    app = { vnet_cidr = "10.10.0.0/16" }
    db  = { vnet_cidr = "10.20.0.0/16" }
  }
  base_workloads = {
    app = {
      vnet_key            = "app"
      subnet_name         = "workload"
      subnet_cidr         = "10.10.1.0/24"
      private_ip          = "10.10.1.10"
      remote_cidr         = "10.20.0.0/16"
      remote_ip           = "10.20.1.10"
      listen_ports        = [8080]
      inbound_test_ports  = ["8080"]
      outbound_test_ports = ["8080", "8081"]
    }
    db = {
      vnet_key            = "db"
      subnet_name         = "workload"
      subnet_cidr         = "10.20.1.0/24"
      private_ip          = "10.20.1.10"
      remote_cidr         = "10.10.0.0/16"
      remote_ip           = "10.10.1.10"
      listen_ports        = [8080, 8081]
      inbound_test_ports  = ["8080", "8081"]
      outbound_test_ports = ["8080"]
    }
  }
  same_vnet_workload = {
    c = {
      vnet_key            = "app"
      subnet_name         = "same-vnet"
      subnet_cidr         = "10.10.2.0/24"
      private_ip          = "10.10.2.20"
      remote_cidr         = "10.10.1.0/24"
      remote_ip           = "10.10.1.10"
      listen_ports        = [8080, 8081]
      inbound_test_ports  = ["8080", "8081"]
      outbound_test_ports = ["8080"]
    }
  }
  workloads = merge(local.base_workloads, var.enable_same_vnet ? local.same_vnet_workload : {})

  # These known-value specifications are also exercised by plan-only mock tests.
  route_specs = {
    for role, workload in local.workloads : role => concat(
      [{ name = "default", prefix = "0.0.0.0/0", type = "VirtualAppliance" }],
      role != "c" && var.explicit_remote_routes ? [
        { name = "remote-spoke", prefix = workload.remote_cidr, type = "VirtualAppliance" }
      ] : [],
      role == "app" && var.enable_same_vnet ? [
        { name = "same-vnet-forward", prefix = "10.10.2.0/24", type = "VirtualAppliance" }
      ] : [],
      role == "c" && var.same_vnet_return_route_enabled ? [
        { name = "same-vnet-return", prefix = "10.10.1.0/24", type = "VirtualAppliance" }
      ] : [],
      role == "db" && var.return_route_blackhole ? [
        { name = "experiment-return-blackhole", prefix = "10.10.1.10/32", type = "None" }
      ] : []
    )
  }
  test_nsg_rules = {
    for role, workload in local.workloads : role => concat([
      { name = "allow-inbound-fixture-tests", priority = 100, direction = "Inbound", source = "${workload.remote_ip}/32", destination = "${workload.private_ip}/32", ports = workload.inbound_test_ports },
      { name = "allow-outbound-fixture-tests", priority = 100, direction = "Outbound", source = "${workload.private_ip}/32", destination = "${workload.remote_ip}/32", ports = workload.outbound_test_ports }
      ], role == "app" && var.enable_same_vnet ? [
      { name = "allow-same-vnet-reverse-test", priority = 101, direction = "Inbound", source = "10.10.2.20/32", destination = "10.10.1.10/32", ports = ["8080"] },
      { name = "allow-same-vnet-forward-tests", priority = 101, direction = "Outbound", source = "10.10.1.10/32", destination = "10.10.2.20/32", ports = ["8080", "8081"] }
    ] : [])
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
  # No customer NSG or route-to-self table on this managed firewall subnet.
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
  name                     = "east-west-policy"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  sku                      = "Standard"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags
  # Standalone policy; no private_ip_ranges override or auto-learn.
  # RFC1918 network-rule destinations retain their original source by default.
  dns {
    proxy_enabled = true
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "east_west" {
  name               = "east-west-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 300

  network_rule_collection {
    name     = "allow-private-fixture"
    priority = 100
    action   = "Allow"
    rule {
      name                  = "allow-app-to-test"
      protocols             = ["TCP"]
      source_addresses      = ["${local.workloads.app.private_ip}/32"]
      destination_addresses = ["${local.workloads.db.private_ip}/32"]
      destination_ports     = ["8080"]
    }
    dynamic "rule" {
      for_each = var.enable_same_vnet ? [1] : []
      content {
        name                  = "allow-app-to-same-vnet"
        protocols             = ["TCP"]
        source_addresses      = ["10.10.1.10/32"]
        destination_addresses = ["10.10.2.20/32"]
        destination_ports     = ["8080"]
      }
    }
  }

  network_rule_collection {
    name     = "deny-negative-fixtures"
    priority = 200
    action   = "Deny"
    rule {
      name                  = "deny-reverse-new"
      protocols             = ["TCP"]
      source_addresses      = ["${local.workloads.db.private_ip}/32"]
      destination_addresses = ["${local.workloads.app.private_ip}/32"]
      destination_ports     = ["*"]
    }
    rule {
      name                  = "deny-app-alternate-port"
      protocols             = ["TCP"]
      source_addresses      = ["${local.workloads.app.private_ip}/32"]
      destination_addresses = ["${local.workloads.db.private_ip}/32"]
      destination_ports     = ["8081"]
    }
    dynamic "rule" {
      for_each = var.enable_same_vnet ? [1] : []
      content {
        name                  = "deny-same-vnet-reverse-new"
        protocols             = ["TCP"]
        source_addresses      = ["10.10.2.20/32"]
        destination_addresses = ["10.10.1.10/32"]
        destination_ports     = ["*"]
      }
    }
    dynamic "rule" {
      for_each = var.enable_same_vnet ? [1] : []
      content {
        name                  = "deny-same-vnet-alternate-port"
        protocols             = ["TCP"]
        source_addresses      = ["10.10.1.10/32"]
        destination_addresses = ["10.10.2.20/32"]
        destination_ports     = ["8081"]
      }
    }
  }
  # No application rules, DNAT, public egress Allows or broad AzureCloud Allows.
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
  depends_on = [azurerm_firewall_policy_rule_collection_group.east_west]
}

resource "azurerm_virtual_network" "workload" {
  for_each            = local.spokes
  name                = each.key
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [each.value.vnet_cidr]
  dns_servers         = [local.firewall_ip]
  tags                = local.tags
}

resource "azurerm_subnet" "workload" {
  for_each                        = local.workloads
  name                            = each.value.subnet_name
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.workload[each.value.vnet_key].name
  address_prefixes                = [each.value.subnet_cidr]
  default_outbound_access_enabled = false
}

# Explicitly serialize peering operations. There is no app-to-db direct peering.
resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.workload["app"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.workload["app"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_app]
}

resource "azurerm_virtual_network_peering" "hub_to_db" {
  name                         = "hub-to-db"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.workload["db"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.app_to_hub]
}

resource "azurerm_virtual_network_peering" "db_to_hub" {
  name                         = "db-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.workload["db"].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_db]
}

resource "azurerm_route_table" "workload" {
  for_each                      = local.workloads
  name                          = "${each.key}-inspect"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  dynamic "route" {
    for_each = local.route_specs[each.key]
    content {
      name                   = route.value.name
      address_prefix         = route.value.prefix
      next_hop_type          = route.value.type
      next_hop_in_ip_address = route.value.type == "VirtualAppliance" ? local.firewall_ip : null
    }
  }
}

resource "azurerm_subnet_route_table_association" "workload" {
  for_each       = local.workloads
  subnet_id      = azurerm_subnet.workload[each.key].id
  route_table_id = azurerm_route_table.workload[each.key].id
}

resource "azurerm_network_security_group" "workload" {
  for_each            = local.workloads
  name                = "${each.key}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.test_nsg_rules[each.key]
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = security_rule.value.destination
    }
  }
  security_rule {
    name                       = "allow-ssh-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.bastion_cidr
    destination_address_prefix = "${each.value.private_ip}/32"
  }
  dynamic "security_rule" {
    for_each = { Udp = 200, Tcp = 201 }
    content {
      name                       = "allow-dns-proxy-${lower(security_rule.key)}"
      priority                   = security_rule.value
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = security_rule.key
      source_port_range          = "*"
      destination_port_range     = "53"
      source_address_prefix      = "${each.value.private_ip}/32"
      destination_address_prefix = "${local.firewall_ip}/32"
    }
  }
  security_rule {
    name                       = "deny-direct-platform-dns"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzurePlatformDNS"
  }
  dynamic "security_rule" {
    for_each = toset(["Inbound", "Outbound"])
    content {
      name                       = "deny-other-${lower(security_rule.key)}"
      priority                   = 4000
      direction                  = security_rule.key
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  for_each                  = local.workloads
  subnet_id                 = azurerm_subnet.workload[each.key].id
  network_security_group_id = azurerm_network_security_group.workload[each.key].id
}

resource "azurerm_network_interface" "workload" {
  for_each            = local.workloads
  name                = "${each.key}-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.workload[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_linux_virtual_machine" "workload" {
  for_each                        = local.workloads
  name                            = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.workload[each.key].id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }
  os_disk {
    name                 = "${each.key}-os"
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
        path        = "/opt/azure-ew-lab/server.py"
        owner       = "root:root"
        permissions = "0644"
        encoding    = "b64"
        content     = filebase64("${path.module}/fixtures/server.py")
      },
      {
        path        = "/etc/systemd/system/azure-ew-fixture@.service"
        owner       = "root:root"
        permissions = "0644"
        encoding    = "b64"
        content     = filebase64("${path.module}/fixtures/azure-ew-fixture@.service")
      },
      {
        path        = "/etc/azure-ew-lab.env"
        owner       = "root:root"
        permissions = "0644"
        content     = "BIND_IP=${each.value.private_ip}\nFIXTURE_ROLE=${each.key}\n"
      },
      {
        path        = "/etc/azure-ew-lab.json"
        owner       = "root:root"
        permissions = "0644"
        content = jsonencode({
          role              = each.key
          private_ip        = each.value.private_ip
          remote_ip         = each.value.remote_ip
          listen_ports      = each.value.listen_ports
          firewall_ip       = local.firewall_ip
          same_vnet_enabled = var.enable_same_vnet
          same_vnet_ip      = "10.10.2.20"
        })
      },
      {
        path        = "/usr/local/bin/ew-ready"
        owner       = "root:root"
        permissions = "0755"
        encoding    = "b64"
        content     = filebase64("${path.module}/scripts/guest-ready.sh")
      },
      {
        path        = "/usr/local/bin/ew-probe"
        owner       = "root:root"
        permissions = "0755"
        encoding    = "b64"
        content     = filebase64("${path.module}/scripts/guest-probe.sh")
      }
    ]
    runcmd = concat(
      [["systemctl", "daemon-reload"]],
      [for port in each.value.listen_ports : ["systemctl", "enable", "--now", "azure-ew-fixture@${port}.service"]],
      [["bash", "-c", "umask 077; /usr/local/bin/ew-ready > /var/log/azure-ew-readiness.log 2>&1"]]
    )
  })]))

  boot_diagnostics {}
  depends_on = [
    azurerm_subnet_route_table_association.workload,
    azurerm_subnet_network_security_group_association.workload,
    azurerm_virtual_network_peering.db_to_hub,
    azurerm_monitor_diagnostic_setting.firewall
  ]
}
