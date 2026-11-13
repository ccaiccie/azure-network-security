# Lab: Service endpoints, Private Endpoint and Private Link Service (Scenario 27)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (service endpoint policies, private endpoint network policies, the Private Link Service NAT blocks and the
`storage_account_id` argument of `azurerm_storage_container` especially) before you apply anything.

## What it builds

* Free baseline: a resource group, a consumer VNet `pl27-vnet-con` 10.50.0.0/16 (subnets snet-se with a Microsoft.Storage service endpoint, snet-pe, snet-plain), a provider VNet `pl27-vnet-prov` 10.60.0.0/16 (snet-backend, a /28 NAT subnet snet-pls) and an NSG on snet-pe. The VNets are deliberately not peered.
* Gate 1 `deploy_vms`: vm-se-1 (10.50.1.10) and vm-plain-1 (10.50.4.10). Billable.
* Gate 2 `deploy_storage`: a storage account with firewall Deny, a VNet rule for snet-se and a container that allows anonymous listing (lab only).
* Gate 3 `deploy_private_endpoint`: a blob private endpoint (10.50.2.5), the `privatelink.blob.core.windows.net` zone, its link and a zone group. Billable.
* Gate 4 `deploy_se_policy`: a service endpoint policy and a second storage account in its own resource group; `attach_se_policy` attaches the policy.
* Gate 5 `deploy_pls`: a backend VM (10.60.1.10), a Standard internal load balancer (10.60.1.100), a Private Link Service and a consumer endpoint (10.50.2.6). Billable.
* Switches: `disable_public_access`, `pe_nsg_deny_se`, `enable_proxy_protocol`, `pls_nat_ip_count`.
* `break_fix`: none, public_open, pe_pending, zone_unlinked, pls_pending or nsg_ignored.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage. A `-var` flag applies to that command only.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Network objects, the service endpoint, endpoint subnet settings, NSG |
| `storage.tf` | Lab and second storage accounts, containers, service endpoint policy |
| `privatelink.tf` | Gated blob private endpoint and privatelink zone |
| `vms.tf`, `pls.tf` | Gated VMs; load balancer, Private Link Service, consumer endpoint |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/backend.py`, `scripts/cloud-init-backend.yaml`, `scripts/diagnose.sh` | Backend server, its boot file, read-only helper |
| `tests/check_contract.py` | Whitespace-tolerant source checks (no Azure, no Terraform) |
| `queries/endpoint-diagnosis-checklist.md` | A one-page diagnosis order |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real SSH key's private half, a subscription secret or any credential into
`terraform.tfvars` that you share. The public key text is not secret. The anonymous container is for the test only: never put real data in it.
