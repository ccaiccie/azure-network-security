# Lab: inspecting Azure Load Balancer traffic with Palo Alto VM-Series (Scenario 43)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply`, no `az` command and no PAN-OS commit has been run for this lab; only `terraform fmt`. Check current
Microsoft and Palo Alto Networks documentation (Marketplace image names and versions, the load balancer and Gateway Load
Balancer resources, PAN-OS set-command syntax and the Gateway LB integration) before you apply anything.

**Cost warning.** Two VM-Series VMs (with a licence you must hold or buy), Standard load balancers, public IPs and two small web
VMs bill by the hour. Every costly stage is behind a gate that defaults to `false`. Destroy the lab the same day. **Accepting the
Marketplace terms is a legal step that you take yourself**; the lab only reads `accept_marketplace_terms` (default `false`).

## What it builds

* Free baseline: resource group, hub VNet `cs43-hub` 10.80.0.0/16 (snet-mgmt, snet-untrust, snet-trust, snet-gwlb), app VNet `cs43-app` 10.81.0.0/16 (snet-web), a peering with forwarded traffic allowed on both sides, five NSGs and an empty route table.
* Gate 1 `deploy_firewalls`: public IPs, NICs with IP forwarding, two VM-Series VMs from a Marketplace image (variables), the public Standard load balancer (rule with floating IP, probe, outbound rule), the internal Standard load balancer 10.80.2.10 with an HA ports rule and a probe, and the web default route.
* Gate 2 `deploy_backends`: two small web VMs and the web internal load balancer 10.81.0.10.
* Gate 3 `deploy_gateway_lb`: a Gateway Load Balancer, a fourth NIC on each firewall, a second public frontend chained to it. Needs gates 1 and 2.

Switches that are not gates: `accept_marketplace_terms`, `vmseries_*`, `bootstrap_*`, `mgmt_source_cidr`, `use_availability_zones`, `enable_nat_gateway`, `enable_accelerated_networking`, `plb_floating_ip`, `nsg_allow_http_inbound`, `break_probe_block`, `probe_port`, `outbound_ports`, `lb_idle_timeout_minutes`, `lb_tcp_reset`.

## Files

| File | Purpose |
|---|---|
| `main.tf`, `routes.tf` | Networks, peering, NSGs, route table and the gated route |
| `firewall.tf`, `loadbalancers.tf`, `backends.tf`, `gwlb.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/web-init.sh` | Boot script for the web VMs |
| `bootstrap/` | PAN-OS set commands, a Gateway LB placeholder, an init-cfg example |
| `LAB-GUIDE.md` | Six activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a secret into `terraform.tfvars` that you share.
