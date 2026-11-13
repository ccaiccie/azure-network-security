locals {
  runtime_configs = {
    app       = { role = "app", private_ip = local.app_ip, app_ip = local.app_ip, origin_ip = local.origin_ip, origin_public_ip = azurerm_public_ip.endpoint["origin"].ip_address, egress_public_ips = [azurerm_public_ip.endpoint["perimeter"].ip_address] }
    origin    = { role = "origin", private_ip = local.origin_ip, app_ip = local.app_ip, origin_ip = local.origin_ip, origin_public_ip = azurerm_public_ip.endpoint["origin"].ip_address, egress_public_ips = [azurerm_public_ip.endpoint["perimeter"].ip_address] }
    perimeter = { role = "perimeter", private_ip = local.perimeter_ip, firewall_private_ip = azurerm_firewall.lab.ip_configuration[0].private_ip_address, app_ip = local.app_ip, origin_public_ip = azurerm_public_ip.endpoint["origin"].ip_address, perimeter_public_ip = azurerm_public_ip.endpoint["perimeter"].ip_address, source_mode = var.source_mode }
  }
  fixture_files = [
    { path = "/opt/azure-forced-lab/server.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../fixtures/server.py")) },
    { path = "/opt/azure-forced-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/probe.py")) },
    { path = "/usr/local/bin/forced-probe", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/forced-probe")) },
    { path = "/usr/local/bin/forced-ready", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/forced-ready")) },
    { path = "/etc/systemd/system/azure-forced-fixture@.service", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../fixtures/azure-forced-fixture@.service")) }
  ]
  perimeter_files = [
    { path = "/opt/azure-forced-lab/controller.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/controller.py")) },
    { path = "/usr/local/sbin/forced-control", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/forced-control")) },
    { path = "/usr/local/sbin/forced-evidence", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/forced-evidence")) },
    { path = "/etc/systemd/system/forced-prepare.service", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/forced-prepare.service")) }
  ]
}
resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.workloads
  name                            = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  source_image_id                 = var.image_id
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
  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = concat([
      { path = "/etc/azure-forced-lab.json", owner = "root:root", permissions = "0644", content = jsonencode(local.runtime_configs[each.key]) }
    ], each.key == "perimeter" ? local.perimeter_files : local.fixture_files)
    runcmd = concat([["systemctl", "daemon-reload"]], each.key == "perimeter" ? [
      ["systemctl", "enable", "--now", "forced-prepare.service"]
      ] : each.key == "origin" ? [
      ["systemctl", "enable", "--now", "azure-forced-fixture@8080.service", "azure-forced-fixture@8081.service", "azure-forced-fixture@8082.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/forced-ready > /var/log/forced-fixture-readiness.log 2>&1"]
    ] : [["bash", "-c", "umask 077; /usr/local/bin/forced-ready > /var/log/forced-client-readiness.log 2>&1"]])
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm, azurerm_subnet_route_table_association.workload, azurerm_subnet_route_table_association.firewall, azurerm_monitor_diagnostic_setting.firewall]
}
