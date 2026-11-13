# Lab: Azure Bastion and Just-in-Time VM access (Scenario 33)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the `azurerm_bastion_host` feature flags, `azurerm_security_center_subscription_pricing`, the Bastion NSG rule set,
the `BastionAuditLogs` category and the az CLI flags) before you apply anything.

## COST WARNING

* **Azure Bastion** (gate 2) bills **per hour from creation** until it is deleted. The default SKU is Basic; Standard and Premium cost more (check current pricing). Stopping the VM does not stop Bastion.
* The **Defender for Servers plan** (gate 3) is **SUBSCRIPTION-WIDE**: it turns the plan on for **every VM** in the subscription and bills **per server per month** (check current pricing). Use a throw-away subscription.
* Both gates default to `false` and each needs a second acknowledgement switch. Destroy in the same sitting.
* **Just-in-Time access is partly portal-only.** Terraform turns on the plan; the JIT policy for vm-app is created in the portal (or with the REST API or Azure Policy). Activity 5 shows the portal steps.

## What it builds

* Free baseline: a resource group, hub VNet `bas33-vnet-hub` 10.33.0.0/16 with `AzureBastionSubnet` 10.33.250.0/26 and its NSG, spoke VNet `bas33-vnet-spoke` 10.34.0.0/16 with `snet-app` 10.34.1.0/24.
* Gate 1 `deploy_workload`: `bas33-vm-app` 10.34.1.4 (no public IP, boot diagnostics), the app NSG (SSH only from the Bastion subnet) and the hub-spoke peering. Small hourly cost.
* Gate 2 `deploy_bastion` + `accept_bastion_cost`: the Bastion host, its Standard static public IP, a workspace and a `BastionAuditLogs` diagnostic setting. **Costly.** Needs gate 1.
* Gate 3 `deploy_defender_servers` + `accept_defender_cost`: the Defender for Servers plan (Plan 2). **Costly and subscription-wide.**
* `vm_public_ip`: a temporary public IP for the JIT demonstration only.
* Bastion options (Standard or higher): `bastion_native_client`, `bastion_ip_connect`, `bastion_shareable_link`; `bastion_session_recording` (Premium).
* Break/fix switches that cost nothing: `bastion_nsg_include_gatewaymanager`, `nic_nsg_blocks_ssh`, `peer_spoke_to_hub`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, hub and spoke VNets, AzureBastionSubnet, Bastion NSG |
| `workload.tf`, `bastion.tf`, `defender.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/bastion-check.sh` | Read-only helper (subnet, nsg, vm, peering, bastion, jit) |
| `scripts/check-lab.sh` | Static check of the lab files; whitespace-tolerant |
| `queries/bastion-queries.kql` | Saved Log Analytics queries |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put secrets into `terraform.tfvars`. The public key text is not secret.
