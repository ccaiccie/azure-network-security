# Lab: outbound connectivity and SNAT (Scenario 22)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the subnet private flag, the NAT gateway prefix association, the load balancer outbound rule and the firewall
policy resources especially) before you apply anything.

## What it builds

* Free baseline: a resource group, VNet `snat22-vnet` 10.50.0.0/16 and three subnets (snet-nat, snet-lb, snet-fw).
* Gate 1 `deploy_vms`: vm-nat 10.50.1.10, vm-lb 10.50.2.10, vm-fw 10.50.3.10 with no public IP. Billable.
* Gate 2 `deploy_nat_gateway`: a NAT gateway with one public IP (or a prefix) attached to snet-nat. Billable per hour and per GB.
* Gate 3 `deploy_lb_outbound`: an outbound-only public Standard load balancer and an outbound rule for vm-lb.
* Gate 4 `deploy_firewall`: Azure Firewall Standard, a policy and a route table that sends snet-fw to it. The most expensive gate.
* Gate 5 `attach_vm_public_ip`: a public IP on vm-nat's NIC, to show NAT gateway precedence.
* Switches that cost nothing: `default_outbound_access_enabled`, `lb_allocated_ports`, `lb_idle_timeout_minutes`, `nat_idle_timeout_minutes`, `nat_public_ip_prefix_length`, `nat_on_fw_subnet`.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Network objects and the private subnet flag |
| `nat.tf`, `lb.tf`, `firewall.tf`, `compute.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/egress-check.sh`, `scripts/snat-burst.sh` | Read-only helper and a small burst tool for the VMs |
| `queries/snat-queries.kql` | A firewall log query and the metric names to chart |
| `LAB-GUIDE.md` | Seven activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a private key, a subscription secret or any credential into
`terraform.tfvars` that you share. The public key text is not secret. The burst script opens real connections: keep the count small
and use a destination you are allowed to test.
