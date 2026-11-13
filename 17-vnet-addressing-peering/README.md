# Scenario 17: VNet addressing, subnets, peering and gateway transit (lab)

A small Terraform lab, **designed, not tested**: it was never initialised, planned, validated or applied in this edition. Only `terraform fmt` and the local source check have been run.

It builds a hub VNet (`10.0.0.0/16`) and two spokes (`10.10.0.0/16`, `10.20.0.0/16`) joined by peering, then lets you switch on, one at a time: test VMs, a direct spoke-to-spoke peering, a forwarding VM in the hub, a global peering to a third spoke in another region, a VPN gateway with gateway transit, and a pretend on-premises site. A `break_fix` switch builds broken setups for the diagnosis drills.

Read `LAB-GUIDE.md` for six activities with commands and expected output.

## Files

| File | What it holds |
|---|---|
| `versions.tf`, `variables.tf` | Provider pin and every variable, including seven gates |
| `main.tf` | Resource group, VNets and subnets |
| `peering.tf` | Every peering link with its four properties |
| `vms.tf`, `nva.tf` | Test VMs, forwarding VM, route tables |
| `gateway.tf` | VPN gateway, local network gateway, connection |
| `outputs.tf` | Address plan, VM IPs, link properties |
| `scripts/` | `nva-cloud-init.yaml` and `diagnose.sh` |
| `tests/check_contract.py` | Whitespace-tolerant source checks (no Azure, no Terraform) |

## Gates (all default to false)

`deploy_vms`, `peer_spokes_directly`, `deploy_nva`, `create_global_peering`, `create_gateway` (costly), `enable_gateway_transit`, `create_onprem_connection` (needs `TF_VAR_vpn_shared_key`).

`break_fix` is `none` by default; other values: `one_sided`, `no_forwarded`, `no_transit`, `overlap`.

## Cost and safety

Virtual networks, subnets and peering links have no hourly charge of their own, but peered traffic is billed per GB (global peering costs more). VMs, the `VpnGw1AZ` gateway and its Standard public IP bill while they exist. Check current Azure pricing. Use a disposable subscription and a new resource group. The VMs have no public IPs and default outbound access is off. The pre-shared key is kept in Terraform state: protect the state. Addresses `203.0.113.10` and `192.168.100.0/24` are illustrative.

Attribute names follow azurerm 4.x (for example `bgp_route_propagation_enabled`, `ip_forwarding_enabled`); check the provider docs for the version you install.
