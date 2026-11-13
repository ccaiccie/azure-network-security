resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.spokes
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
      { path = "/etc/azure-partner-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value.ip, app_ip = local.app_ip, origin_ip = local.origin_ip, origin_public_ip = azurerm_public_ip.origin.ip_address, egress_public_ips = [] }) },
      { path = "/opt/azure-partner-lab/server.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/server.py") },
      { path = "/opt/azure-partner-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/probe.py") },
      { path = "/usr/local/bin/partner-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/partner-probe") },
      { path = "/usr/local/bin/partner-ready", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/partner-ready") },
      { path = "/etc/systemd/system/azure-partner-fixture@.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/azure-partner-fixture@.service") }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      each.key == "origin" ? ["systemctl", "enable", "--now", "azure-partner-fixture@8080.service", "azure-partner-fixture@8081.service"] : ["true"],
      ["bash", "-c", "umask 077; /usr/local/bin/partner-ready > /var/log/partner-fixture-readiness.log 2>&1"]
    ]
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm]
}
