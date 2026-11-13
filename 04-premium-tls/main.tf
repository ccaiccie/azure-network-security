module "lab" {
  count                       = var.deploy_lab ? 1 : 0
  source                      = "./module"
  subscription_id             = var.subscription_id
  resource_group_name         = var.resource_group_name
  location                    = var.location
  admin_username              = var.admin_username
  ssh_public_key              = var.ssh_public_key
  vm_size                     = var.vm_size
  image_version               = var.image_version
  operator_cidr               = var.operator_cidr
  origin_name                 = var.origin_name
  deploy_lab                  = var.deploy_lab
  enable_tls_inspection       = var.enable_tls_inspection
  tls_prerequisites_confirmed = var.tls_prerequisites_confirmed
  origin_fixture_ready        = var.origin_fixture_ready
  tls_secret_uri              = var.tls_secret_uri
  tls_identity_id             = var.tls_identity_id
  tags                        = var.tags
}
