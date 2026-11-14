# Lab: AKS to AKS traffic enforcement with Palo Alto VM-Series (Scenario 42)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply`, no `az` or `kubectl` command and no PAN-OS commit has been run for this lab; only `terraform fmt`. Check current
Microsoft and Palo Alto Networks documentation (Marketplace image names and versions, the AKS network profile, the load balancer
resources, PAN-OS set-command syntax) before you apply anything.

**Cost warning.** Two VM-Series VMs (with a licence you must hold or buy), a Standard internal load balancer, public IPs and two AKS nodes bill
by the hour. Every costly stage is behind a gate that defaults to `false`. Destroy the lab the same day. **Accepting the Marketplace terms is
a legal step that you take yourself**; the lab only reads `accept_marketplace_terms` (default `false`).

## What it builds

* Free baseline: resource group, hub VNet `cs42-hub` 10.70.0.0/16 (snet-mgmt, snet-untrust, snet-trust), spoke VNets `cs42-spoke-a` 10.71.0.0/16 and `cs42-spoke-b` 10.72.0.0/16, four peerings with forwarded traffic allowed, NSGs, and two route tables (no routes yet).
* Gate 1 `deploy_firewalls`: public IPs, six NICs with IP forwarding, two VM-Series VMs from a Marketplace image (variables), the internal Standard load balancer 10.70.2.10 with an HA ports rule and a TCP probe, and the routes in both route tables.
* Gate 2 `deploy_aks`: two identities, role assignments and two AKS clusters (Azure CNI node subnet, outbound type userDefinedRouting, one small node). Needs gate 1.
* Gate 3 `enable_cheap_layer`: NSG rules on both node subnets (free). The NetworkPolicies are manifests applied with kubectl.

Switches that are not gates: `accept_marketplace_terms`, `vmseries_publisher`, `vmseries_offer`, `vmseries_sku`, `vmseries_version`, `bootstrap_*`, `mgmt_source_cidr`, `use_availability_zones`, `cni_mode`, `b_reply_next_hop_override`. Changing `cni_mode` replaces the clusters.

## Files

| File | Purpose |
|---|---|
| `main.tf`, `routes.tf` | Networks, peerings, NSGs, route tables and the gated routes |
| `firewall.tf`, `aks.tf`, `cheap.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `manifests/` | Apps, policies, RBAC (applied with kubectl) |
| `scripts/register-pod-tags.sh` | Registers pod labels as tags through the PAN-OS XML API |
| `bootstrap/` | PAN-OS set commands and an init-cfg example |
| `LAB-GUIDE.md` | Six activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a secret into `terraform.tfvars` that you share.
