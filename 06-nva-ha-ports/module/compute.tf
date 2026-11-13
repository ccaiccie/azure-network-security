resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.private_ips
  name                            = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  source_image_id                 = var.image_id
  zone                            = contains(keys(local.nvas), each.key) && var.nva_zones != null ? var.nva_zones[each.key == "nva1" ? 0 : 1] : null
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
  # Guest policy/health tests are explicit local actions, not Terraform inputs.
  # They never modify cloud-init and do not require replacing the VM.
  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = concat([
      { path = "/etc/azure-nva-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value, app_ip = local.app_ip, backend_ip = local.backend_ip, frontend_ip = local.frontend_ip }) },
      { path = "/opt/azure-nva-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/probe.py") },
      { path = "/usr/local/bin/nva-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/nva-probe") },
      { path = "/usr/local/bin/backend-ready", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/backend-ready") }
      ], each.key == "backend" ? [
      { path = "/opt/azure-nva-lab/server.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/server.py") },
      { path = "/etc/systemd/system/azure-nva-fixture@.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/azure-nva-fixture@.service") }
      ] : [], contains(keys(local.nvas), each.key) ? [
      { path = "/opt/azure-nva-lab/controller.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/controller.py") },
      { path = "/usr/local/bin/nva-control", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/nva-control") },
      { path = "/usr/local/bin/nva-evidence", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/nva-evidence") },
      { path = "/etc/systemd/system/nva-boot.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/nva-boot.service") },
      { path = "/etc/systemd/system/nva-health-monitor.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/nva-health-monitor.service") },
      { path = "/etc/systemd/system/nva-health.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/nva-health.service") }
    ] : [])
    runcmd = each.key == "backend" ? [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "azure-nva-fixture@8080.service", "azure-nva-fixture@8081.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/backend-ready > /var/log/azure-nva-backend-readiness.log 2>&1"]
      ] : contains(keys(local.nvas), each.key) ? [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "nva-boot.service", "nva-health-monitor.service", "nva-health.service"]
    ] : []
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm, azurerm_subnet_route_table_association.spoke, azurerm_subnet_route_table_association.nva, azurerm_virtual_network_peering.backend_to_hub, azurerm_lb_rule.ha]
}
