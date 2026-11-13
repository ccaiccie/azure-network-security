# Lab: BGP path selection and selective routing (Scenario 37)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (`azurerm_route_server`, `azurerm_route_server_bgp_connection`, `bgp_route_propagation_enabled`, the gateway `bgp_enabled` and `bgp_settings`)
before you apply anything. The FRR setup on the NVAs is also untested.

## What it builds

* Free baseline: a resource group, VNet `bgp37-hub` 10.37.0.0/16 with RouteServerSubnet 10.37.0.0/27, snet-nva 10.37.1.0/24, snet-app 10.37.2.0/24 and GatewaySubnet 10.37.255.0/27, and a route table on snet-app.
* Gate 1 `deploy_route_server`: Azure Route Server (ASN 65515) and a Standard public IP. Billable by the hour.
* Gate 2 `deploy_nvas`: two FRR NVAs (nva-a 10.37.1.4 ASN 65001, nva-b 10.37.1.5 ASN 65002), the two Route Server peerings, and vm-app 10.37.2.4. Both NVAs originate 10.99.0.0/24 (the simulated on-premises prefix). Billable. Needs gate 1 and your public key.
* Gate 3 `deploy_vpn_gateway` (optional): a BGP-enabled VPN gateway in GatewaySubnet. Billable and slow. No tunnel peer exists in this lab.
* Free switches: `branch_to_branch`, `app_bgp_route_propagation`, `blackhole_prefix`, `nva_a_asn`, `nva_b_asn`.

All gates default to false. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNet, subnets, route table |
| `routeserver.tf`, `nvas.tf`, `vpngw.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/frr-setup.sh.tftpl`, `scripts/frr-render.sh` | Boot script and FRR renderer for the NVAs |
| `scripts/frr-policy.sh` | Run on an NVA: change prepend, local preference, MED, communities, prefixes, summaries |
| `scripts/bgp-check.sh` | Read-only helper for Azure and FRR views |
| `queries/bgp-queries.kql` | Gateway diagnostic log queries (optional) |
| `tests/check-gates.sh` | Static check that every gate defaults to false |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real secret into `terraform.tfvars`. The public key text is not secret.
Route Server and any gateway are the costly objects: open their gates only when you need them, and destroy when you finish.
