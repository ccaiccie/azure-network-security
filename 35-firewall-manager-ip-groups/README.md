# Lab: Azure Firewall Manager, policy inheritance and IP groups (Scenario 35)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the `azurerm_firewall_policy` settings and `insights` block, rule collection group arguments such as `source_ip_groups`,
`azurerm_ip_group`, the Azure Policy alias for the firewall policy id, and the `az network firewall policy` and `ip-group` property names) before you apply anything.

## COST WARNING

* **Azure Firewall** (gate 1) bills **per hour from creation** until it is deleted, plus data processing (check current pricing). A Premium firewall costs more than Standard. Deallocating is not available for the lab firewall: destroy it.
* The firewall policies, rule collection groups and IP groups have no hourly charge by themselves as understood here (check current pricing, especially for policies with several firewall associations).
* The workspace (gate 2) has a small ingestion and retention cost.
* Gate 1 needs two switches and defaults to `false`. Destroy the firewall in the same sitting.

## What it builds

* Free baseline: a resource group, five IP groups (`ipg-spokes`, `ipg-app-a`, `ipg-app-b`, `ipg-shared`, `ipg-blocked`), the parent policy `fm35-fp-parent` with three rule collection groups (100 DNAT, 200 network, 300 application), and child policies `fm35-fp-child-a` and `fm35-fp-child-b`.
* Gate 1 `deploy_firewall` + `accept_firewall_cost`: hub VNet 10.60.0.0/16, `AzureFirewallSubnet` 10.60.250.0/26, a Standard static public IP and one Azure Firewall that uses `firewall_policy_choice` (child-a by default). **Costly.**
* Gate 2 `deploy_analytics`: a Log Analytics workspace, policy insights on the parent and a firewall diagnostic setting with resource-specific tables.
* Gate 3 `deploy_policy_audit`: a custom Azure Policy definition and an audit assignment on the lab resource group. Free; nothing is denied.
* `policy_sku`: Standard or Premium (Premium adds IDPS on the parent; check pricing).
* Break/fix switches that cost nothing: `child_allow_blocked_range`, `ipg_app_a_missing_prefix`, `associate_policy_to_firewall` (needs gate 1), `child_conflicting_dnat`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, locals and the five IP groups |
| `policies.tf` | Parent and child policies, rule collection groups, break/fix blocks |
| `firewall.tf`, `analytics.tf`, `governance.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/policy-check.sh` | Read-only helper (parent, children, groups, ipgroups, settings, firewall, audit) |
| `scripts/check-lab.sh` | Static check of the lab files; whitespace-tolerant |
| `queries/firewall-policy-queries.kql` | Saved Log Analytics queries |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put secrets into `terraform.tfvars`.
