# Scenario 16: ExpressRoute multi-region lab

**Designed, not tested.** This Terraform module was never initialised, planned or applied, and no Azure CLI command was run. Every command in `LAB-GUIDE.md` is a procedure for a future run you decide to make. Reading the guide needs no circuit and no Azure account.

## What it builds

Two regional hubs, each with a GatewaySubnet and an ExpressRoute gateway, peered to a spoke (hub-to-spoke peering with gateway transit, spoke-to-hub with remote gateways). Optionally two ExpressRoute circuit resources, a private peering on each, and four gateway connections with weights. Optionally one small VM per spoke and a Log Analytics workspace.

There is no simulated on-premises router. A simulation cannot hold a BGP session with a real Microsoft edge, so the steering activities (local preference, prepend, failover) are run by you on your own router against a real or provider test circuit.

## Gates (all default to false)

`deploy_lab`, `deploy_er_gateways`, `deploy_test_vms`, `create_circuits`, `configure_private_peering`, `create_connections`, `enable_diagnostics`. With every gate closed, `terraform plan` creates nothing.

## Cost and safety

ExpressRoute gateways bill by the hour. Circuits bill from creation and need a connectivity provider; the service key is handed over out of band. Destroy what you create.

## Files

`versions.tf`, `variables.tf`, `main.tf`, `network.tf`, `gateways.tf`, `circuits.tf`, `connections.tf`, `vms.tf`, `diagnostics.tf`, `outputs.tf`, `terraform.tfvars.example`, `scripts/er-evidence.sh`, `queries/*.kql`, `router/pseudo-policy.txt`. See `LAB-GUIDE.md` for the activities.

Argument names follow `azurerm` 4.x as remembered. Check the provider documentation for the version you install. All addresses are RFC 1918 or RFC 5737 examples and the ASNs are private examples.
