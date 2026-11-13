# Lab: Container networking and security inspection (Scenario 38)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` or `kubectl` command has been run for this lab; only `terraform fmt`. Check current Microsoft
docs and the provider docs (the AKS network profile, the firewall policy rule blocks and the diagnostic categories especially) before you apply anything.

**Cost warning.** Azure Firewall bills by the hour as long as it exists, and an AKS cluster adds a node and load balancer frontends. The lab uses
the Basic firewall SKU, one `Standard_B2s` node and the Free control plane tier. Every costly stage is behind a gate that defaults to `false`. Destroy the lab the same day.

## What it builds

* Free baseline: a resource group, hub VNet `cs38-hub` 10.60.0.0/16 (AzureFirewallSubnet, AzureFirewallManagementSubnet), spoke VNet `cs38-spoke` 10.61.0.0/16 (snet-nodes) with peering both ways, and a route table on snet-nodes (no routes yet).
* Gate 1 `deploy_firewall`: two public IPs, a firewall policy with the AKS FQDN tag rule and a test rule, the firewall, and the default and firewall-IP routes. Billable.
* Gate 2 `deploy_aks`: a managed identity, role assignments and one AKS cluster (Azure CNI Overlay, outbound type userDefinedRouting). Needs gate 1. Billable.
* Gate 3 `enable_dnat`: a DNAT rule from the firewall public IP to the internal load balancer address. Needs gate 1.
* Gate 4 `enable_diagnostics`: a Log Analytics workspace and a firewall diagnostic setting. Billed per GB.

Switches that are not gates: `cni_mode`, `network_policy`, `firewall_sku`, `include_fqdn_tag_rule`, `egress_rule_source`, `add_legacy_network_rules`, `bypass_client_cidr`, `private_cluster`, `api_authorized_ranges`, ranges. Changing `cni_mode`, `network_policy` or `private_cluster` replaces the cluster.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Network objects, peering, node route table |
| `firewall.tf`, `aks.tf` | Gated firewall and cluster stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `manifests/` | Echo app, network policies, Services (applied with kubectl) |
| `scripts/` | The egress probe helper |
| `LAB-GUIDE.md` | Six activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a secret into `terraform.tfvars` that you share.
