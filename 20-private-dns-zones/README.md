# Lab: Azure DNS and private DNS zones (Scenario 20)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the private DNS zone link, the private endpoint zone group and the VNet DNS server settings especially) before you apply anything.

## What it builds

* Free baseline: a resource group, two VNets that are deliberately not peered (`dns20-vnet-app` 10.40.0.0/16, `dns20-vnet-spoke` 10.41.0.0/16), the private zone `lab20.example` with a registration link (app) and a resolution link (spoke), and two static records.
* Gate 1 `deploy_vms`: vm-app-1 (10.40.1.10) and vm-spoke-1 (10.41.1.10). Billable.
* Gate 2 `deploy_custom_dns`: dns-fwd (10.40.3.10), a tiny forwarder, and the DNS server setting of the app VNet. Billable.
* Gate 3 `deploy_private_endpoint`: a storage account, a blob private endpoint with a zone group, the `privatelink.blob.core.windows.net` zone and its links.
* Gate 4 `create_public_zone`: a public zone with the same name as the private zone, for split-horizon. Not delegated.
* `break_fix`: none, no_spoke_link, no_zone_group, pe_zone_unlinked, public_forwarder or stale_record.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Network objects, the private zone, links and static records |
| `vms.tf` | Gated VMs and NICs (clients and forwarder) |
| `privatelink.tf`, `publiczone.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/dnsq.py`, `scripts/forward.py`, `scripts/cloud-init-*.yaml`, `scripts/diagnose.sh` | DNS client, forwarder, boot files, read-only helper |
| `tests/check_contract.py` | Whitespace-tolerant source checks (no Azure, no Terraform) |
| `queries/dns-diagnosis-checklist.md` | A one-page diagnosis order |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real SSH key's private half, a subscription secret or any credential into
`terraform.tfvars` that you share. The public key text is not secret.
