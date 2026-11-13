# Lab: Virtual WAN site-to-site and ExpressRoute routing (Scenario 32)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the hub `hub_routing_preference`, the connection `routing` blocks, `static_vnet_route`, the VPN gateway
`bgp_settings` instance attributes and `azurerm_virtual_hub_bgp_connection`) before you apply anything. The strongSwan and FRR setup on vm-edge and vm-nva is also untested.

**Cost warning.** A Standard virtual hub bills by the hour and takes a while to create. VPN and ExpressRoute gateways bill per scale unit per hour (the ER gateway even with no circuit). Check current pricing. Every costly stage is behind a gate that defaults to `false`.

## What it builds

* Free baseline: a resource group, a Standard Virtual WAN `vwan32-wan`, and four spoke VNets: prod 10.101.0.0/24, dev 10.102.0.0/24, shared 10.103.0.0/24 (region 1) and eu2 10.201.0.0/24 (region 2).
* Gate 1 `deploy_hub1`: hub1 10.100.0.0/24, custom route tables `rt-spokes` [spokes] and `rt-branch` [branch] beside the built-in Default and None, and the prod, dev and shared connections with the association and propagation settings described in `hub.tf`.
* Gate 2 `deploy_vms`: one small VM per spoke (no public IPs). Needs `admin_ssh_public_key`.
* Gate 3 `deploy_branch_sim`: a simulated branch 10.80.0.0/16: vm-edge 10.80.0.10 (strongSwan and FRR, ASN 65020, public IP) and vm-lan 10.80.2.10.
* Gate 4 `deploy_vpn`: hub1 VPN gateway, VPN site and connection with BGP; the connection reads `rt-branch`. Needs gates 1 and 3 and a lab-only `shared_key`.
* Gate 5 `deploy_hub2`: hub2 10.200.0.0/24 in the second region, tables carrying the labels `spokes` and `branch`, and the eu2 connection.
* Gate 6 `deploy_er_gateway`: an ExpressRoute gateway in hub1. No circuit is created; set `er_circuit_peering_id` only if you own one.
* Gate 7 `deploy_nva_bgp`: vm-nva 10.103.0.10 (FRR, ASN 65030) and a hub BGP connection to it.
* Switches that cost nothing: `fault` (none, label_typo, shared_none, branch_assoc_default), `hub_routing_preference`, `allow_branch_to_branch`, `static_routes`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, Virtual WAN, spoke VNets |
| `hub.tf` | Hubs, custom route tables, VNet connections (gates 1, 5) |
| `vpn.tf`, `branch.tf`, `vms.tf` | VPN and ER gateways, the simulated branch, VMs and the NVA (gates 2, 3, 4, 6, 7) |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/onprem-setup.sh.tftpl`, `scripts/nva-setup.sh.tftpl` | Boot scripts (templates) for vm-edge and vm-nva |
| `scripts/vwan-check.sh` | Read-only helper: tables, effective routes, pings |
| `queries/vwan-queries.kql` | Gateway diagnostic log queries |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real key or secret into `terraform.tfvars`. The `shared_key` is stored in Terraform state
and in the VM's custom data, so use a throwaway value. The public key text is not secret. Hubs and gateways are the costly objects: open
their gates late and destroy when you finish.
