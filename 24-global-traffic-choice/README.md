# Lab: Choosing between Traffic Manager, Front Door, Application Gateway and Load Balancer (Scenario 24)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (Front Door, Traffic Manager and Application Gateway resources especially) before you apply anything.

## What it builds

One region and one VNet with two small nginx web servers. They are reachable three ways: a public Standard Load Balancer (layer 4),
an Application Gateway v2 (layer 7, regional) and a Front Door Standard profile (layer 7, global) that uses the gateway as its origin.
A Traffic Manager profile chooses by DNS between the gateway (priority 1) and the load balancer (priority 2). The web servers print the
peer address and the forwarding headers, so every path shows what it changes.

## Gates (all `false` by default)

* Gate 1 `deploy_backends`: two VMs and a public Standard load balancer (billable).
* Gate 2 `deploy_app_gateway`: Application Gateway Standard_v2 (billed per hour plus capacity units). Needs gate 1.
* Gate 3 `deploy_front_door`: Front Door Standard profile, endpoint, origin group, origin, route. Needs gate 2.
* Gate 4 `deploy_traffic_manager`: profile and two external endpoints. Needs gate 2.

Switches used by the activities: `probe_path`, `appgw_probe_path`, `tm_routing_method`, `tm_ttl_seconds`, `tm_probe_interval_seconds`,
`tm_tolerated_failures`, `appgw_only_from_front_door`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, VNet, two subnets, two NSGs with rules |
| `compute.tf`, `lb.tf` | Gate 1: web VMs and the Standard load balancer |
| `appgw.tf`, `frontdoor.tf`, `trafficmanager.tf` | Gates 2, 3 and 4 |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/cloud-init-web.yaml`, `scripts/verify.sh`, `scripts/failover-timer.sh` | Boot script and read-only helpers |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Set `my_ip_cidr` to your own public address as a /32. Never put a private key, a subscription
secret or any credential into `terraform.tfvars` that you share. The public key text is not secret.
