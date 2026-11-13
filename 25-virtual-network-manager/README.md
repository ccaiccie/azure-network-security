# Lab: Azure Virtual Network Manager (Scenario 25)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the network manager, group, connectivity, admin rule and deployment resources and the policy definition
especially) before you apply anything.

## What it builds

* Free baseline: a resource group, a hub VNet 10.70.0.0/24 and spokes a, b, c (10.71 to 10.73.0.0/24) with `env` tags.
* Gate 1 `deploy_avnm`: a network manager scoped to the subscription and a static group (spoke-a, spoke-b).
* Gate 2 `deploy_connectivity`: hub-and-spoke configurations v1 and v2 (direct connectivity) and a deployment of the one in `active_connectivity`.
* Gate 3 `deploy_security_admin`: an admin configuration, one rule collection and two rules, committed.
* Gate 4 `deploy_dynamic_group`: a dynamic group filled by a custom Azure Policy (`env = prod`) and a subscription-level assignment.
* Gate 5 `deploy_vms`: three small VMs (HTTP on the app port) and an NSG. Billable.
* Gate 6 `deploy_second_region`: spoke-d in a second region (a free VNet).
* Switches that cost nothing: `active_connectivity`, `admin_rule_action`, `nsg_allows_app_port`, `deployment_regions`, `spoke_c_env`, `use_hub_gateway`, `delete_existing_peering`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage. The lab creates no public IPs.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNets, subnets, tags |
| `avnm.tf`, `connectivity.tf`, `security.tf`, `dynamic.tf`, `deploy.tf`, `vms.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/avnm-check.sh`, `scripts/cloud-init.yaml.tftpl` | Read-only helper and the VM boot template |
| `queries/avnm-queries.kql` | Activity-log query and notes on evidence |
| `tests/check_contract.py` | Whitespace-tolerant source checks (reads files only) |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. The policy assignment in gate 4 covers the whole subscription: use a sandbox subscription.
The public key text in `admin_ssh_public_key` is not secret; never put a private key or credential in `terraform.tfvars`.
