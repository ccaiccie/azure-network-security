module "lab" {
  source                        = "./module"
  count                         = var.deploy_lab ? 1 : 0
  subscription_id               = var.subscription_id
  resource_group_name           = var.resource_group_name
  location                      = var.location
  admin_username                = var.admin_username
  ssh_public_key                = var.ssh_public_key
  vm_size                       = var.vm_size
  image_id                      = var.image_id
  client_public_ip              = var.client_public_ip
  image_prerequisites_confirmed = var.image_prerequisites_confirmed
  deploy_lab                    = var.deploy_lab
  appliances_ready              = var.appliances_ready
  application_ready             = var.application_ready
  enable_chain                  = var.enable_chain
  test_paths_enabled            = var.test_paths_enabled
}
