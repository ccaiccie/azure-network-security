locals {
  hub_cidr      = "10.0.0.0/16"
  firewall_cidr = "10.0.1.0/26"
  bastion_cidr  = "10.0.2.0/26"
  app_ip        = "10.10.1.10"
  firewall_ip   = azurerm_firewall.lab.ip_configuration[0].private_ip_address
  rules_enabled = var.enable_tls_inspection && var.origin_fixture_ready
  tags          = merge(var.tags, { purpose = "disposable-tls-lab", managed_by = "terraform" })
  app_nsg_rules = {
    allow-bastion-ssh        = { priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source = local.bastion_cidr, destination = "${local.app_ip}/32", port = "22" }
    allow-dns-udp            = { priority = 100, direction = "Outbound", access = "Allow", protocol = "Udp", source = "${local.app_ip}/32", destination = "${local.firewall_ip}/32", port = "53" }
    allow-dns-tcp            = { priority = 101, direction = "Outbound", access = "Allow", protocol = "Tcp", source = "${local.app_ip}/32", destination = "${local.firewall_ip}/32", port = "53" }
    allow-https-to-internet  = { priority = 110, direction = "Outbound", access = "Allow", protocol = "Tcp", source = "${local.app_ip}/32", destination = "Internet", port = "443" }
    deny-direct-platform-dns = { priority = 200, direction = "Outbound", access = "Deny", protocol = "*", source = "*", destination = "AzurePlatformDNS", port = "*" }
    deny-other-inbound       = { priority = 4000, direction = "Inbound", access = "Deny", protocol = "*", source = "*", destination = "*", port = "*" }
    deny-other-outbound      = { priority = 4000, direction = "Outbound", access = "Deny", protocol = "*", source = "*", destination = "*", port = "*" }
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
  # No customer NSG/UDR or forced tunnel on this managed subnet.
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
  sku                      = "Premium"
  threat_intelligence_mode = "Alert"
  tags                     = local.tags
  dns { proxy_enabled = true }
  intrusion_detection { mode = "Deny" }
  dynamic "identity" {
    for_each = var.enable_tls_inspection ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.tls_identity_id]
    }
  }
  dynamic "tls_certificate" {
    for_each = var.enable_tls_inspection ? [1] : []
    content {
      name                = "approved-inspection-intermediate"
      key_vault_secret_id = var.tls_secret_uri
    }
  }
  # Only references. Never read/import/generate CA secret values or create access grants.
}
resource "azurerm_firewall_policy_rule_collection_group" "tls" {
  count              = local.rules_enabled ? 1 : 0
  name               = "test-rules"
  firewall_policy_id = azurerm_firewall_policy.lab.id
  priority           = 200
  application_rule_collection {
    name     = "deny-test-url"
    priority = 100
    action   = "Deny"
    rule {
      name             = "deny-blocked-path"
      source_addresses = ["${local.app_ip}/32"]
      destination_urls = ["${azurerm_linux_web_app.origin.default_hostname}/blocked"]
      terminate_tls    = true
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
  application_rule_collection {
    name     = "allow-test-origin"
    priority = 200
    action   = "Allow"
    rule {
      name              = "allow-approved-origin"
      source_addresses  = ["${local.app_ip}/32"]
      destination_fqdns = [azurerm_linux_web_app.origin.default_hostname]
      terminate_tls     = true
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
  # No network443 bypass or blanket network443 deny. No DNAT or application HTTP allow.
}
resource "azurerm_firewall" "lab" {
  name                = "lab-firewall"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.lab.id
  tags                = local.tags
  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
  depends_on = [azurerm_firewall_policy_rule_collection_group.tls]
}
resource "azurerm_virtual_network" "app" {
  name                = "app"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.10.0.0/16"]
  dns_servers         = [local.firewall_ip]
  tags                = local.tags
}
resource "azurerm_subnet" "app" {
  name                            = "workload"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.app.name
  address_prefixes                = ["10.10.1.0/24"]
  default_outbound_access_enabled = false
}
resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                         = "hub-to-app"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.app.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                         = "app-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.app.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network_peering.hub_to_app]
}
resource "azurerm_route_table" "app" {
  name                          = "app-inspect"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  bgp_route_propagation_enabled = false
  tags                          = local.tags
  route {
    name                   = "default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.firewall_ip
  }
}
resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app.id
}
resource "azurerm_network_security_group" "app" {
  name                = "app-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = local.app_nsg_rules
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
resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}
resource "azurerm_network_interface" "app" {
  name                = "app-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.app_ip
  }
}
resource "azurerm_linux_virtual_machine" "app" {
  name                            = "app"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app.id]
  tags                            = local.tags
  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }
  os_disk {
    name                 = "app-os"
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
      { path = "/usr/local/lib/azure-tls/public-ca-check.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../scripts/public-ca-check.py") },
      { path = "/usr/local/bin/tls-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/guest-probe.sh") },
      { path = "/usr/local/bin/tls-capture-chain", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/capture-chain.sh") },
      { path = "/etc/azure-tls-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ app_ip = local.app_ip, firewall_ip = local.firewall_ip, origin_host = azurerm_linux_web_app.origin.default_hostname }) }
    ]
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_subnet_route_table_association.app, azurerm_subnet_network_security_group_association.app, azurerm_virtual_network_peering.app_to_hub, azurerm_monitor_diagnostic_setting.firewall]
}
