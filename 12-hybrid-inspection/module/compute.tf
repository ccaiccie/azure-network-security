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
    write_files = [
      { path = "/etc/azure-hybrid-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value.ip, branch_ip = local.branch_ip, spoke_ip = local.spoke_ip }) },
      { path = "/opt/azure-hybrid-lab/server.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../fixtures/server.py")) },
      { path = "/opt/azure-hybrid-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/probe.py")) },
      { path = "/usr/local/bin/hybrid-probe", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/hybrid-probe")) },
      { path = "/usr/local/bin/hybrid-ready", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/hybrid-ready")) },
      { path = "/etc/systemd/system/azure-hybrid-fixture@.service", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../fixtures/azure-hybrid-fixture@.service")) }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      each.key == "branch" ? ["systemctl", "enable", "--now", "azure-hybrid-fixture@8082.service"] : ["systemctl", "enable", "--now", "azure-hybrid-fixture@8080.service", "azure-hybrid-fixture@8081.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/hybrid-ready > /var/log/hybrid-fixture-readiness.log 2>&1"]
    ]
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm, azurerm_subnet_route_table_association.branch, azurerm_subnet_route_table_association.spoke, azurerm_monitor_diagnostic_setting.firewall]
}
