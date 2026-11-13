# Lab: capstone multi-region network (reference skeleton)

**This is a reference skeleton, not a full deployment.** It is the wiring diagram of the capstone in code: two small hubs, peering, route tables, firewall policy, private DNS zone links, resolvers and an optional on-premises simulation. **Designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command has been run; only `terraform fmt`. Check current Microsoft docs and the provider docs before you apply anything.

## What it builds (every stage is gated, every gate defaults to false)

| Gate | Builds |
|---|---|
| `deploy_region_a`, `deploy_region_b` | Resource group, hub 10.20.0.0/22 or 10.22.0.0/22 with six subnets, three spokes, four route tables, an NSG |
| `enable_peering` | Hub-to-spoke peerings and the global hub-to-hub peering |
| `deploy_firewall_policy` | A base Premium policy and a child policy per region with example rules |
| `link_private_dns` | `privatelink.blob.core.windows.net` linked to each hub (and one spoke) |
| `deploy_firewalls` | BILLABLE: a Premium firewall per region |
| `deploy_resolvers` | BILLABLE: a DNS Private Resolver per hub with a forwarding ruleset |
| `deploy_onprem_sim` | VNet 10.200.0.0/16 standing in for on-premises |
| `deploy_vpn_sim` | BILLABLE and slow: VPN gateways and a BGP tunnel |

## What it does not build

ExpressRoute, Front Door, Application Gateway, AKS, the DDoS plan, Bastion, AVNM, workload VMs, load balancers, flow logs and monitoring. These are covered on paper in the guide.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Address plan, resource groups, hubs, spokes, subnets, route tables, NSG |
| `peering.tf`, `firewall.tf`, `dns.tf`, `onprem.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, pins, outputs |
| `tests/check-gates.sh`, `tests/check-plan-addresses.sh` | Static checks, no Azure calls |
| `LAB-GUIDE.md` | Five activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real secret into `terraform.tfvars`; pass the VPN key through an environment variable. Destroy the billable gates first when you finish.
