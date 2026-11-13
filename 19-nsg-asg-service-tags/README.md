# Lab: NSG, application security groups and service tags (Scenario 19)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the flow log and Virtual Network Manager resources especially) before you apply anything.

## What it builds

* Free baseline: a resource group, VNet `nsg19-vnet` 10.30.0.0/16, three subnets (web, app, pe), two ASGs, two NSGs with their rules.
* Gate 1 `deploy_vms`: web-1 (10.30.1.10, asg-web) and app-1 (10.30.2.10, asg-app, listener on tcp/8080). Billable.
* Gate 2 `attach_nic_nsg`: an NSG on app-1's NIC. Free.
* Gate 3 `deploy_private_endpoint`: a storage account, a blob private endpoint and nsg-pe. Small hourly cost.
* Gate 4 `enable_flow_logs`: a virtual network flow log and its storage account.
* Gate 5 `enable_avnm_demo`: a Virtual Network Manager with one security admin rule, deployed. Affects every VNet in its network group.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf`, `nsg.tf` | Network objects, ASGs, NSGs and rules |
| `compute.tf` | Gated VMs and NICs |
| `privateendpoint.tf`, `flowlogs.tf`, `avnm.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/cloud-init-app.yaml`, `scripts/verify.sh` | Boot script and read-only helper |
| `queries/` | A traffic analytics query and a flow tuple field guide |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real SSH key's private half, a subscription secret or any credential into
`terraform.tfvars` that you share. The public key text is not secret.
