locals {
  runtime_configs = { for role, ip in local.clients : role => {
    role                 = role
    private_ip           = ip
    firewall_private_ip  = azurerm_firewall.lab.ip_configuration[0].private_ip_address
    endpoint_ip          = local.endpoint_ip
    storage_account_name = var.storage_account_name
    blob_fqdn            = local.blob_fqdn
    container            = local.container_name
    blob_name            = local.blob_name
  } }
}
resource "azurerm_linux_virtual_machine" "client" {
  for_each                        = local.clients
  name                            = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.client[each.key].id]
  source_image_id                 = var.image_id
  tags                            = local.tags
  identity { type = "SystemAssigned" }
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
      { path = "/etc/azure-pe-lab.json", owner = "root:root", permissions = "0644", content = jsonencode(local.runtime_configs[each.key]) },
      { path = "/opt/azure-pe-lab/probe.py", owner = "root:root", permissions = "0644", encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/probe.py")) },
      { path = "/usr/local/bin/pe-probe", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/pe-probe")) },
      { path = "/usr/local/bin/pe-ready", owner = "root:root", permissions = "0755", encoding = "gz+b64", content = base64gzip(file("${path.module}/../scripts/pe-ready")) }
    ]
    # No boot-time token acquisition, blob upload/read or automatic network probe.
  })]))
  boot_diagnostics {}
  depends_on = [azurerm_network_interface_security_group_association.client, azurerm_subnet_route_table_association.client]
}
