module "lab" {
  count                 = var.deploy_lab ? 1 : 0
  source                = "./module"
  subscription_id       = var.subscription_id
  resource_group_name   = var.resource_group_name
  location              = var.location
  admin_username        = var.admin_username
  ssh_public_key        = var.ssh_public_key
  vm_size               = var.vm_size
  image_version         = var.image_version
  deploy_lab            = var.deploy_lab
  fixtures_ready        = var.fixtures_ready
  policy_mode           = var.policy_mode
  experiments_confirmed = var.experiments_confirmed
  tags                  = var.tags
}
