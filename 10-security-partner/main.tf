module "lab" {
  count                          = var.deploy_lab ? 1 : 0
  source                         = "./module"
  subscription_id                = var.subscription_id
  resource_group_name            = var.resource_group_name
  location                       = var.location
  admin_username                 = var.admin_username
  ssh_public_key                 = var.ssh_public_key
  vm_size                        = var.vm_size
  image_id                       = var.image_id
  egress_public_ips              = var.egress_public_ips
  vpn_scale_unit                 = var.vpn_scale_unit
  deploy_lab                     = var.deploy_lab
  image_prerequisites_confirmed  = var.image_prerequisites_confirmed
  enable_spp                     = var.enable_spp
  provider_onboarding_verified   = var.provider_onboarding_verified
  tunnels_verified               = var.tunnels_verified
  provider_routing_configured    = var.provider_routing_configured
  enable_source_default          = var.enable_source_default
  protected_routes_verified      = var.protected_routes_verified
  fixtures_ready                 = var.fixtures_ready
  provider_block_policy_verified = var.provider_block_policy_verified
  test_paths_enabled             = var.test_paths_enabled
  provider_profile               = var.provider_profile
  tags                           = var.tags
}
