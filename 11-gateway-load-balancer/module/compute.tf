locals {
  nva_files = {
    "guest/controller.py"        = { path = "/opt/azure-gwlb-lab/controller.py", mode = "0644" }
    "scripts/gwlb-control"       = { path = "/usr/local/sbin/gwlb-control", mode = "0755" }
    "scripts/gwlb-evidence"      = { path = "/usr/local/sbin/gwlb-evidence", mode = "0755" }
    "guest/gwlb-prepare.service" = { path = "/etc/systemd/system/gwlb-prepare.service", mode = "0644" }
    "guest/gwlb-monitor.service" = { path = "/etc/systemd/system/gwlb-monitor.service", mode = "0644" }
    "guest/gwlb-health.service"  = { path = "/etc/systemd/system/gwlb-health.service", mode = "0644" }
  }
  app_files = {
    "fixtures/server.py"                     = { path = "/opt/azure-gwlb-lab/server.py", mode = "0644" }
    "scripts/gwlb-app-ready"                 = { path = "/usr/local/bin/gwlb-app-ready", mode = "0755" }
    "fixtures/azure-gwlb-fixture@.service"   = { path = "/etc/systemd/system/azure-gwlb-fixture@.service", mode = "0644" }
    "fixtures/azure-gwlb-app-health.service" = { path = "/etc/systemd/system/azure-gwlb-app-health.service", mode = "0644" }
  }
}
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
    write_files = concat([
      {
        path        = each.key == "app" ? "/etc/azure-gwlb-app.json" : "/etc/azure-gwlb-lab.json"
        owner       = "root:root"
        permissions = "0644"
        content = each.key == "app" ? jsonencode({ backend_ip = local.backend_ip }) : jsonencode({
          role               = each.key
          private_ip         = each.value.ip
          gwlb_frontend_ip   = local.gwlb_ip
          client_public_ip   = var.client_public_ip
          consumer_public_ip = azurerm_public_ip.consumer.ip_address
          backend_ip         = local.backend_ip
          underlay_mtu       = 1550
          inner_mtu          = 1500
        })
      }
      ], [for filename, spec in(each.key == "app" ? local.app_files : local.nva_files) : {
        path        = spec.path
        owner       = "root:root"
        permissions = spec.mode
        encoding    = "gz+b64"
        content     = base64gzip(file("${path.module}/../${filename}"))
    }])
    runcmd = [
      ["systemctl", "daemon-reload"],
      each.key == "app" ? ["systemctl", "enable", "--now", "azure-gwlb-fixture@8080.service", "azure-gwlb-fixture@8081.service", "azure-gwlb-app-health.service"] : ["systemctl", "enable", "--now", "gwlb-prepare.service", "gwlb-monitor.service", "gwlb-health.service"],
      each.key == "app" ? ["bash", "-c", "umask 077; /usr/local/bin/gwlb-app-ready > /var/log/gwlb-app-readiness.log 2>&1"] : ["true"]
    ]
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm]
}
