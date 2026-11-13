# Lab: ExpressRoute Direct, FastPath, Global Reach and resiliency (Scenario 34)

A small Terraform lab for the guide and deck in the parent folder. **Designed, not tested**: no `terraform init`, `plan`,
`validate` or `apply` and no `az` command has been run for this lab; only `terraform fmt`. Check current Microsoft docs and the
provider docs (the gateway, `azurerm_express_route_circuit`, `azurerm_express_route_port`, `express_route_gateway_bypass`,
`azurerm_express_route_circuit_connection`) before you apply anything.

## What this lab can and cannot do

ExpressRoute needs a connectivity provider or physical fibre at a peering location. **No Terraform lab can honestly provision that.**
The lab therefore builds what Azure can build by itself (VNets, an ExpressRoute gateway, alerts, a test VM), models the circuit,
the connection with the FastPath setting, Global Reach and the Direct port behind gates that default to `false`, and adds offline tools
and captured fixtures so that you can practise the diagnosis without a circuit.

## What it builds

* Free baseline: a resource group, hub VNet `er34-hub` 10.80.0.0/16 (GatewaySubnet 10.80.255.0/27, snet-app 10.80.1.0/24), spoke VNet `er34-spoke` 10.81.0.0/16 and the peering.
* Gate 1 `deploy_er_gateway`: the ExpressRoute gateway (`ErGw1AZ` by default) and its zone-redundant public IP. Hourly bill, slow (30 to 45 minutes or more).
* Gate 2 `deploy_circuit`: a partner circuit. Bills from creation. Needs a provider contract.
* Gate 3 `deploy_connection`: the connection from the gateway to a circuit, with `enable_fastpath`. Needs a provisioned circuit and `circuit_provisioned_confirmed = true`.
* Gate 4 `deploy_direct_port`: an ExpressRoute Direct port and a circuit on it. Needs physical fibre. Bills hourly.
* Gate 5 `deploy_global_reach`: Global Reach between two circuits with an unused /29. Needs two private peering ids.
* Gate 6 `deploy_test_vm`: a small VM to read effective routes.
* Gate 7 `deploy_alerts`: action group, Log Analytics workspace, gateway diagnostic setting and metric alerts.

All gates default to `false`. Setting a gate back to `false` and applying destroys that stage.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Resource group, hub and spoke VNets, subnets, peering |
| `gateway.tf`, `circuit.tf`, `connection.tf`, `globalreach.tf`, `vm.tf`, `alerts.tf` | Gated stages |
| `variables.tf`, `versions.tf`, `outputs.tf`, `terraform.tfvars.example` | Inputs, versions, outputs |
| `scripts/er-check.sh` | Read-only Azure CLI helper |
| `scripts/er-tools.py` | Offline overlap, capacity and triage tools (Python 3 only) |
| `scripts/fixtures/*.json` | Four captured break/fix cases |
| `queries/er-queries.kql` | Log Analytics queries |
| `LAB-GUIDE.md` | Eight activities with commands and expected results |

## Use

Start with `LAB-GUIDE.md`, Activity 1. Never put a real secret into `terraform.tfvars`. The gateway is the costly object you can create
alone: open gate 1 early and destroy when you finish. A circuit or Direct port keeps billing until it is deleted and, for a partner
circuit, released by the provider.
