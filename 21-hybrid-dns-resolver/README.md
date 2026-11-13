# Lab: Hybrid DNS with Azure DNS Private Resolver (Scenario 21)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the resolver resources especially) before you apply anything.

## What it builds

A hub VNet with a DNS Private Resolver (one inbound and one outbound endpoint), a spoke VNet, and a second VNet that stands in for
an on-premises site with its own DNS server (dnsmasq). A forwarding ruleset sends `corp.example.com` to the site; the site forwards
`blob.core.windows.net` to the inbound endpoint. A private endpoint for a storage account shows private-endpoint name resolution.
The peerings stand in for an ExpressRoute or VPN path.

## Gates (all `false` by default)

* Gate 1 `deploy_resolver`: the resolver and its two endpoints. Billed per endpoint hour; check current pricing.
* Gate 2 `deploy_ruleset`: the forwarding ruleset, two rules and the VNet links. Needs gate 1.
* Gate 3 `deploy_vms`: spoke-vm, onprem-dns and onprem-client (billable).
* Gate 4 `deploy_private_endpoint`: storage account, privatelink zone, hub link and blob private endpoint.

Switches used by the activities: `link_spoke_to_ruleset`, `link_hub_to_ruleset`, `corp_forward_target`, `spoke_uses_inbound_dns`.
Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNets, subnets (two delegated), peerings, DNS settings |
| `resolver.tf`, `ruleset.tf` | Gate 1 and gate 2 |
| `compute.tf`, `privateendpoint.tf` | Gate 3 and gate 4 |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/cloud-init-onprem-dns.yaml.tftpl`, `scripts/cloud-init-tools.yaml`, `scripts/verify.sh` | Boot scripts and the read-only helper |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real SSH key's private half, a subscription secret or any credential into
`terraform.tfvars` that you share. The public key text is not secret.
