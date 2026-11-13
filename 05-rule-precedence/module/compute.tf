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
  # No policy mode is embedded here: switching policy is not a VM replacement.
  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = concat([
      { path = "/etc/azure-policy-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value.private_ip, backend_ip = local.backend_ip, firewall_ip = local.firewall_ip, allowed_host = "allowed.policy.test", denied_host = "denied.policy.test" }) },
      { path = "/usr/local/bin/policy-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/guest-probe.sh") },
      { path = "/usr/local/bin/policy-ready", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/guest-ready.sh") }
      ], each.key == "backend" ? [
      { path = "/opt/azure-policy-lab/server.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/server.py") },
      { path = "/etc/systemd/system/azure-policy-fixture@.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/azure-policy-fixture@.service") },
      { path = "/etc/azure-policy-lab.env", owner = "root:root", permissions = "0644", content = "BIND_IP=${local.backend_ip}\n" }
    ] : [])
    runcmd = each.key == "backend" ? [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "azure-policy-fixture@8080.service", "azure-policy-fixture@8081.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/policy-ready > /var/log/azure-policy-readiness.log 2>&1"]
    ] : []
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_subnet_route_table_association.workload, azurerm_subnet_network_security_group_association.workload, azurerm_virtual_network_peering.backend_to_hub, azurerm_private_dns_zone_virtual_network_link.hub, azurerm_private_dns_a_record.origin, azurerm_monitor_diagnostic_setting.firewall]
}
