# Scenario 18: system routes, user-defined routes and effective routes

**Designed, not tested.** Never applied to Azure. Opening these files executes nothing. Only `terraform fmt` was run while authoring.

A small lab with three Linux VMs (no public IPs, no Bastion, no gateway, no firewall), two peered VNets and two route tables. A client `vm-a` reaches a web server `vm-b` through an appliance `vm-nva` only when the gated routes are on. See `LAB-GUIDE.md` for the five activities.

| Item | Value |
|---|---|
| vnet-a | 10.10.0.0/16: snet-app 10.10.1.0/24 (vm-a 10.10.1.10, rt-app), snet-nva 10.10.2.0/24 (vm-nva 10.10.2.10, no table) |
| vnet-b | 10.20.0.0/16: snet-work 10.20.1.0/24 (vm-b 10.20.1.20, web on 8080, rt-work) |
| Gates (default false) | `deploy_lab`, `enable_udr_forward`, `enable_return_route`, `enable_blackhole_route`, `enable_default_route`, `enable_service_tag_route` |
| Settings | `bgp_route_propagation_enabled` (default true), `fault` (none, forwarding_off, missing_association, return_only) |

## Files

`versions.tf`, `variables.tf`, `main.tf`, `network.tf`, `compute.tf`, `routes.tf`, `outputs.tf`; `cloud-init/nva.yaml.tftpl` (forwarding, stateful iptables, no SNAT) and `cloud-init/web.yaml.tftpl` (web server); `scripts/check-source.sh` (offline, whitespace-tolerant source checks); `terraform.tfvars.example`.

## Notes

* The provider is pinned to the AzureRM 4.x series. Argument names such as `bgp_route_propagation_enabled`, `ip_forwarding_enabled` and `default_outbound_access_enabled` follow that series: check the provider documentation.
* The VMs are controlled with `az vm run-command invoke` so no public IP or Bastion is needed.
* A route table does nothing until it is associated with a subnet, and `snet-nva` never gets one.
* The lab creates and destroys its own resource group. Destroy it when finished: `terraform destroy`.
* The state may contain the SSH public key you provide. Never provide a private key.
