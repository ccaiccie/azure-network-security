module "lab" {
  count                         = var.deploy_lab ? 1 : 0
  source                        = "./module"
  subscription_id               = var.subscription_id
  resource_group_name           = var.resource_group_name
  location                      = var.location
  admin_username                = var.admin_username
  ssh_public_key                = var.ssh_public_key
  vm_size                       = var.vm_size
  image_id                      = var.image_id
  frr_version                   = var.frr_version
  deploy_lab                    = var.deploy_lab
  image_prerequisites_confirmed = var.image_prerequisites_confirmed
  tags                          = var.tags
}
