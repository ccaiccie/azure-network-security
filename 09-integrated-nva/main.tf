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
  deploy_lab                    = var.deploy_lab
  image_prerequisites_confirmed = var.image_prerequisites_confirmed
  vendor_ready                  = var.vendor_ready
  enable_internet_intent        = var.enable_internet_intent
  fixtures_ready                = var.fixtures_ready
  internet_routes_verified      = var.internet_routes_verified
  vendor_deny_policy_verified   = var.vendor_deny_policy_verified
  test_paths_enabled            = var.test_paths_enabled
  egress_public_ips             = var.egress_public_ips
  vendor_profile                = var.vendor_profile
  tags                          = var.tags
}
