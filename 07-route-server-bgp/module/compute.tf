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
      { path = "/etc/azure-routeserver-lab.json", owner = "root:root", permissions = "0644", content = jsonencode({ role = each.key, private_ip = each.value, app_ip = local.app_ip, remote_ip = local.remote_ip, destination_ip = local.destination_ip, rs_peer_ips = local.rs_peer_ips, rs_asn = local.rs_asn, frr_version = var.frr_version }) }
      ], each.key == "app" ? [
      { path = "/opt/azure-routeserver-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/probe.py") },
      { path = "/usr/local/bin/rs-probe", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/rs-probe") }
      ] : [], each.key != "app" ? [
      { path = "/opt/azure-routeserver-lab/controller.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/controller.py")) },
      { path = "/usr/local/bin/rs-control", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/rs-control") },
      { path = "/usr/local/bin/rs-evidence", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/rs-evidence") },
      { path = "/etc/systemd/system/rs-boot.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/rs-boot.service") }
      ] : [], each.key == "remote" ? [
      { path = "/opt/azure-routeserver-lab/server.py", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/server.py") },
      { path = "/usr/local/bin/remote-ready", owner = "root:root", permissions = "0755", encoding = "b64", content = filebase64("${path.module}/../scripts/remote-ready") },
      { path = "/etc/systemd/system/azure-routeserver-fixture@.service", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../fixtures/azure-routeserver-fixture@.service") }
      ] : [], contains(keys(local.nvas), each.key) ? [
      { path = "/etc/frr/daemons", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/frr-daemons") },
      { path = "/etc/systemd/system/frr.service.d/rs-lab.conf", owner = "root:root", permissions = "0644", encoding = "b64", content = filebase64("${path.module}/../guest/frr-lab.conf") }
    ] : [])
    runcmd = each.key == "remote" ? [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "rs-boot.service", "azure-routeserver-fixture@8080.service", "azure-routeserver-fixture@8081.service"],
      ["bash", "-c", "umask 077; /usr/local/bin/remote-ready > /var/log/rs-remote-readiness.log 2>&1"]
      ] : contains(keys(local.nvas), each.key) ? [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "rs-boot.service", "frr.service"]
    ] : []
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.vm, azurerm_subnet_route_table_association.spoke, azurerm_subnet_route_table_association.nva, azurerm_virtual_network_peering.remote_to_hub, azurerm_route_server_bgp_connection.nva]
}
