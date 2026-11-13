# Lab: network observability with Network Watcher (Scenario 28)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the flow log, Connection Monitor, firewall and diagnostic setting resources especially) before you apply anything.

## What it builds

* Free baseline: a resource group, a client VNet 10.80.0.0/24, a server VNet 10.81.0.0/24, two peerings and an NSG on the server subnet.
* Gate 1 `deploy_vms`: vm-client 10.80.0.10 and vm-server 10.81.0.10 (HTTP on the app port) with the Network Watcher agent. Billable.
* Gate 2 `deploy_monitoring`: a Log Analytics workspace and a storage account.
* Gate 3 `deploy_flow_logs`: VNet flow logs on both VNets, with Traffic Analytics unless switched off.
* Gate 4 `deploy_connection_monitor`: a Connection Monitor from vm-client to vm-server.
* Gate 5 `deploy_firewall`: a hub VNet 10.82.0.0/24, Azure Firewall Standard, a policy, route tables and structured logs. Expensive; the only public IP.
* Switches that cost nothing: `nsg_allows_app_port`, `symmetric_return`, `traffic_analytics_enabled`, `traffic_analytics_interval`, `monitor_protocol`, `monitor_rtt_threshold_ms`, `create_network_watcher`, `app_port`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNets, NSG, peerings, Network Watcher lookup |
| `vms.tf`, `monitoring.tf`, `flowlogs.tf`, `connmon.tf`, `firewall.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/netwatch-check.sh`, `scripts/cloud-init.yaml.tftpl` | Helper (read-mostly) and the VM boot template |
| `queries/netwatch-queries.kql` | The KQL cookbook for the lab |
| `tests/check_contract.py` | Whitespace-tolerant source checks (reads files only) |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. The public key text in `admin_ssh_public_key` is not secret; never put a private key or credential in `terraform.tfvars`.
Flow logs, Traffic Analytics and the firewall bill by volume or by the hour: destroy the stages you finish with.
