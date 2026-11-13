resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.nodes
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
      { path = "/etc/azure-spp-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value.ip, app_ip = local.app_ip, origins = { for k, ip in local.origins : k => { private_ip = ip, public_ip = azurerm_public_ip.origin[k].ip_address } }, egress_public_ips = [] }) },
      { path = "/opt/azure-spp-lab/server.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/server.py") },
      { path = "/opt/azure-spp-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/probe.py") },
      { path = "/usr/local/bin/spp-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/spp-probe") },
      { path = "/usr/local/bin/spp-ready", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/spp-ready") },
      { path = "/etc/systemd/system/azure-spp-fixture.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/azure-spp-fixture.service") }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      each.key != "app" ? ["systemctl", "enable", "--now", "azure-spp-fixture.service"] : ["true"],
      ["bash", "-c", "umask 077; /usr/local/bin/spp-ready > /var/log/spp-fixture-readiness.log 2>&1"]
    ]
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm]
}
