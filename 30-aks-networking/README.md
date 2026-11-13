# Lab: AKS networking foundations (Scenario 30)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` or `kubectl` command has been run for this lab; only `terraform fmt`. Check current Microsoft
docs and the provider docs (the AKS network profile, the application routing block and the outbound types especially) before you apply anything.

**Cost warning.** An AKS cluster is costly compared with the other labs. The lab uses one `Standard_B2s` node, the Free control plane tier and
the AKS Standard Load Balancer. Every costly stage is behind a gate that defaults to `false`. Destroy the lab the same day.

## What it builds

* Free baseline: a resource group, VNet `aks30-vnet` 10.40.0.0/16 (snet-nodes, snet-nodes2), a stand-in VNet `aks30-onprem` 10.50.0.0/16 with peering both ways, an NSG on the stand-in subnet, and the private DNS zone `lab30.internal` with record `db` = 10.50.1.4.
* Gate 1 `deploy_aks`: a managed identity, a network role and one AKS cluster (Azure CNI Overlay by default). Billable.
* Gate 2 `deploy_onprem_vm`: the stand-in VM `onprem-1` (10.50.1.4) with a listener on tcp/8080. Billable.
* Gate 3 `enable_app_routing`: the managed NGINX ingress add-on (needs gate 1).
* Gate 4 `add_second_pool`: a second node pool in snet-nodes2 (needs gate 1). Billable.

Switches that are not gates: `cni_mode`, `enable_cilium`, `outbound_type`, `private_cluster`, `api_authorized_ranges`, `link_private_zone`, `onprem_allowed_source`, ranges. Changing the first four replaces the cluster.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Network objects, peering, stand-in NSG, private zone |
| `aks.tf`, `onprem.tf` | Gated cluster stages and the stand-in VM |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `manifests/` | Echo app, Services, Ingress, CoreDNS customisation (applied with kubectl) |
| `scripts/` | Stand-in boot script and the sizing helper |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a private key, a subscription secret or any credential into `terraform.tfvars` that you share. The public key text is not secret.
