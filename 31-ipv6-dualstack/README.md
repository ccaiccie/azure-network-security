# Lab: IPv6 and dual stack on Azure (Scenario 31)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (dual-stack subnet `address_prefixes`, the IP configuration `primary` and `private_ip_address_version` arguments, IPv6
`azurerm_public_ip`, `azurerm_lb_rule` and `default_outbound_access_enabled` especially) before you apply anything.

All IPv6 examples use the documentation prefix 2001:db8::/32 (RFC 3849). Azure may or may not accept it as a VNet range: if it
refuses, set `ipv6_vnet_prefix` to a ULA /48 such as `fd00:db8:31::/48`. Azure assigns the real private IPv6 addresses of the NICs.

## What it builds

* Free baseline: a resource group, a dual-stack VNet `ds31-vnet` (10.31.0.0/16 and an IPv6 /48), subnets `snet-web` and `snet-client`
  (each one IPv4 prefix and one IPv6 /64, with default outbound access off), an NSG with separate IPv4 and IPv6 allow rules for TCP 8080,
  an empty route table on `snet-client` and a private DNS zone `ds31.internal`.
* Gate 1 `deploy_vms`: vm-web-1 (10.31.1.10) and vm-client-1 (10.31.2.10) with a second, IPv6 IP configuration on each NIC, and the A and AAAA records. Billable.
* Gate 2 `deploy_lb`: a Standard public load balancer with an IPv4 and an IPv6 frontend, one pool, probe and rule per family. Billable. Needs gate 1.
* Gate 3 `deploy_client_ips`: a public IPv4 and a public IPv6 on vm-client-1. Billable. Needs gate 1.
* Gate 4 `deploy_peer`: a second dual-stack VNet (10.32.0.0/16 and an IPv6 /48) and two peerings.
* `break_fix`: none, nsg_v4_only, no_aaaa or udr_v4_only.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage. A `-var` flag applies to that command only.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Dual-stack VNet and subnets, NSG, route table, private DNS zone |
| `vms.tf` | Gated dual-stack VMs, client public IPs, A and AAAA records |
| `lb.tf`, `peer.tf` | Gated dual-stack load balancer; gated second VNet and peerings |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/cloud-init-web.yaml`, `scripts/diagnose.sh` | VM boot file, read-only helper (curl by family) |
| `tests/check_contract.py` | Whitespace-tolerant source checks (no Azure, no Terraform) |
| `queries/ipv6-diagnosis-checklist.md` | A one-page diagnosis order |
| `LAB-GUIDE.md` | Five activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a private key, a subscription secret or any credential into `terraform.tfvars`
that you share. The public key text is not secret.
