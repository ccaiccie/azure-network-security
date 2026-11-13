# Lab: Azure DDoS Protection (Scenario 29), defensive only

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (`ddos_protection_mode` on `azurerm_public_ip`, the `ddos_protection_plan` block on the VNet, the diagnostic log
categories and the metric name `IfUnderDDoSAttack`) before you apply anything.

**The lab is defensive only. It enables protection, diagnostics and alert rules. It never generates traffic and contains no attack
tooling. Testing DDoS protection goes only through a Microsoft-approved simulation partner.**

## COST WARNING

* A **DDoS protection plan** (gate 3) costs roughly **thousands of US dollars per month** and bills from creation, even with no VNet linked.
* **DDoS IP Protection** (gate 4) costs a few hundred US dollars **per protected IP per month**.
* These figures are approximate; check current Azure pricing. Both gates default to `false`; the plan also needs `accept_ddos_plan_cost = true`. Destroy in the same sitting.

## What it builds

* Free baseline: a resource group, VNet `ddos29-vnet` 10.90.0.0/16, subnet `snet-web` 10.90.1.0/24 and an NSG that allows tcp/80 and tcp/443.
* Gate 1 `deploy_workload`: `vm-web` 10.90.1.4 (nginx, no SSH rule), Standard public IP `pip-web` (attached) and `pip-spare` (attached to nothing). Small hourly cost.
* Gate 2 `deploy_monitoring`: Log Analytics workspace, diagnostic setting on `pip-web` (three DDoS log categories and metrics), action group and a metric alert on the under attack metric. Needs gate 1.
* Gate 3 `deploy_ddos_network_protection` + `accept_ddos_plan_cost`: a DDoS protection plan linked to the VNet. **Costly.**
* Gate 4 `deploy_ip_protection`: protection mode `Enabled` on `pip-web`. **Costly.** The lab refuses to enable gates 3 and 4 together.
* Break/fix switches that cost nothing: `link_vnet_to_plan`, `pip_web_mode_override`, `alert_on_spare_ip_by_mistake`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNet (optional plan link), subnet, NSG |
| `workload.tf`, `monitoring.tf`, `ddos.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/ddos-check.sh` | Read-only helper (tier, ip, diag, alerts, metrics) |
| `scripts/check-lab.sh` | Static check of the lab files; whitespace-tolerant |
| `queries/ddos-queries.kql` | Saved Log Analytics queries |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put secrets into `terraform.tfvars`. The public key text is not secret.
