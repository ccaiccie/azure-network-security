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
  fixtures_ready                = var.fixtures_ready
  private_routes_verified       = var.private_routes_verified
  perimeter_ready               = var.perimeter_ready
  origin_access_enabled         = var.origin_access_enabled
  test_paths_enabled            = var.test_paths_enabled
  allow_test_flow               = var.allow_test_flow
  snat_comparison_acknowledged  = var.snat_comparison_acknowledged
  source_mode                   = var.source_mode
  tags                          = var.tags
}
