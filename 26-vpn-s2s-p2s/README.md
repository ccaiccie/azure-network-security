# Lab: site-to-site and point-to-site VPN design (Scenario 26)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the gateway `bgp_settings` and `peering_addresses`, `vpn_client_configuration`, the connection `ipsec_policy`
and `use_policy_based_traffic_selectors`) before you apply anything. The strongSwan and FRR setup on vm-edge is also untested.

## What it builds

* Free baseline: a resource group, VNet `vpn26-hub` 10.60.0.0/16 with GatewaySubnet 10.60.255.0/27 and snet-app 10.60.1.0/24.
* Gate 1 `deploy_vpn_gateway`: the VPN gateway (`VpnGw1AZ` by default) and its zone-redundant public IP(s). Billable by the hour and slow (30 to 45 minutes or more).
* Gate 2 `deploy_onprem_sim`: a simulated site `vpn26-onprem` 10.70.0.0/16. vm-edge 10.70.0.10 is the VPN device (strongSwan + FRR) with a public IP and an NSG for UDP 500 and 4500, vm-lan 10.70.2.10 sits behind it with a route to Azure through vm-edge, and vm-app 10.60.1.10 is in Azure. Billable.
* Gate 3 `deploy_s2s`: the local network gateway and the IPsec connection. Needs gates 1 and 2 and a `shared_key` of 16 or more characters (lab-only).
* Gate 4 `deploy_p2s`: point-to-site on the gateway: pool 172.16.201.0/24, OpenVPN and IKEv2, certificate or Entra ID authentication.
* Switches that cost nothing: `active_active` (decide before gate 1), `enable_bgp`, `use_apipa`, `custom_ipsec_policy`, `dpd_timeout_seconds`, `lng_prefixes`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, Azure VNet, subnets |
| `vpn.tf`, `s2s.tf`, `onprem.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/onprem-setup.sh.tftpl` | Boot script (template) for vm-edge: strongSwan, FRR, tunnel interfaces, MSS clamp |
| `scripts/onprem-bgp.sh`, `scripts/onprem-fault.sh` | Run on vm-edge: BGP configuration and the break/fix faults |
| `scripts/vpn-check.sh`, `scripts/mtu-test.sh` | Read-only helper and a packet-size test |
| `queries/vpn-queries.kql` | Gateway diagnostic log queries and metric names |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real key or secret into `terraform.tfvars`. The `shared_key` is stored in Terraform state
and in the VM's custom data, so use a throwaway value. The public key text is not secret. The VPN gateway is the costly object: open gate 1
early, and destroy when you finish.
