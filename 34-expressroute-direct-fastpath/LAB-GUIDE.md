# Lab guide: ExpressRoute Direct, FastPath, Global Reach and resiliency

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab **cannot** create a real ExpressRoute circuit or Direct port by itself: they need a provider contract or physical fibre. Without one, run gates 2 to 5 as plans only and use the offline tools and fixtures.

## Activity 1: Plan the free baseline and run the two offline tools

**Goal.** Create the free hub and spoke VNets, then use two offline helper scripts to check a Global Reach range and a Direct port plan before any money is spent.

**Exam skill:** Know the GatewaySubnet rule, that a /29 must not overlap anything, and how oversubscription is calculated for circuits on a Direct port.

1. **Prepare the inputs and format the code**: From the `terraform` folder copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds a resource group, two VNets, three subnets and two peerings. No gateway, no public IP, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. Outputs `gateway_name` and `circuit_id` are empty.

3. **Check a Global Reach range offline**: The script needs only Python 3. It uses the standard `ipaddress` module and talks to nothing.

   ```bash
   python3 scripts/er-tools.py overlap 192.0.2.8/29 172.16.10.0/24 172.16.20.0/24 10.80.0.0/16
   ```

   Expect: `OK: 192.0.2.8/29 is a /29 and overlaps nothing` and the two /30 halves 192.0.2.8/30 and 192.0.2.12/30.

4. **Break it on purpose**

   ```bash
   python3 scripts/er-tools.py overlap 172.16.10.0/29 172.16.10.0/24 172.16.20.0/24
   ```

   Expect: `OVERLAP: 172.16.10.0/29 is inside 172.16.10.0/24`. This is the Global Reach prefix-overlap fault in miniature.

5. **Plan a Direct port with circuits**

   ```bash
   python3 scripts/er-tools.py capacity 10 5 5 5 2
   ```

   Expect: Port 10 Gbps, circuits total 17 Gbps, ratio 1.7: oversubscribed, with a warning to check the current limit. Change the numbers to see the verdicts change.

6. **Checkpoint**: Why can the baseline not contain a Global Reach or Direct resource? Answer: both need a provider or a physical port, so they sit behind gates 4 and 5 and are never created by default.

## Activity 2: Create the ExpressRoute gateway and read the VM routes

**Goal.** Open gate 1 (the ER gateway) and gate 6 (a test VM), then read the gateway and the VM's effective routes.

**Exam skill:** Know what an ExpressRoute gateway needs, that it is slow and billed by the hour, and that an AZ SKU needs a zone-redundant Standard public IP.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_er_gateway = true`. Keep `gateway_sku = "ErGw1AZ"`. Decide the SKU before the first apply.

   ```bash
   terraform plan -out=gw.tfplan
   terraform apply gw.tfplan
   ```

   Expect: One Standard public IP and the gateway. Creation often takes 30 to 45 minutes or more. (Designed, not tested.)

2. **Open gate 6**: Set `deploy_test_vm = true` and paste your public key text into `admin_ssh_public_key`.

   ```bash
   terraform plan -out=vm.tfplan
   terraform apply vm.tfplan
   ```

   Expect: A small VM in snet-app with a private address only. Output `vm_private_ip` is 10.80.1.4 or similar.

3. **Read the gateway**

   ```bash
   ./scripts/er-check.sh gateway
   ```

   Expect: SKU `ErGw1AZ`, type `ExpressRoute`, provisioning state `Succeeded`.

4. **Read the VM's effective routes**

   ```bash
   ./scripts/er-check.sh effective
   ```

   Expect: `10.80.0.0/16 VnetLocal`, `10.81.0.0/16 VNetPeering` and `0.0.0.0/0 Internet`. No on-premises prefix yet: no circuit is connected.

5. **Checkpoint**: What changes in the effective routes when a circuit is connected and BGP learns 172.16.10.0/24? Answer: a route with next hop `Virtual network gateway` and source BGP appears.

## Activity 3: Create the alerts for the circuit, the gateway and the traffic

**Goal.** Open gate 7 to create an action group, a Log Analytics workspace, gateway diagnostic settings and metric alerts, so that monitoring exists before the first circuit does.

**Exam skill:** Know which metrics matter: availability, bits in and out, drops, gateway CPU and packets per second, and which alert maps to which failure.

1. **Open gate 7**: Set `deploy_alerts = true` and `alert_email` to a mailbox you own. The gateway CPU alert needs gate 1 as well.

   ```bash
   terraform plan -out=alerts.tfplan
   terraform apply alerts.tfplan
   ```

   Expect: An action group, a workspace, a diagnostic setting and a CPU alert on the gateway. Circuit alerts are added only when a circuit id exists.

2. **List the metrics that exist**

   ```bash
   ./scripts/er-check.sh metrics-defs
   ```

   Expect: A list that includes `ExpressRouteGatewayCpuUtilization` and `ExpressRouteGatewayPacketsPerSecond`. Names can change: compare with current docs.

3. **Read a recent value**

   ```bash
   ./scripts/er-check.sh cpu
   ```

   Expect: A low CPU percentage per five minutes. With no traffic it is close to zero.

4. **Checkpoint**: Which alert would have caught a gateway that is saturated by small packets while bandwidth is low? Answer: the packets-per-second or CPU alert, not the bandwidth alert.

## Activity 4: Plan a circuit, or a Direct port and circuit, and read the status fields

**Goal.** Read a circuit plan, and if you own a provider contract or a Direct port, create the circuit and read the fields that say whether it is ready.

**Exam skill:** Know the difference between circuit status and provider status, and the service key.

1. **Read the plan only**: Set `deploy_circuit = true`, `service_provider_name` and `peering_location` to values that match your provider. **Do not apply** unless you have a contract: the circuit bills from creation, before the provider provisions it.

   ```bash
   terraform plan -out=ckt.tfplan
   ```

   Expect: One circuit with your SKU and bandwidth. No Direct port. Read the plan, then stop if you have no provider.

2. **Direct variant**: Set `deploy_direct_port = true` instead. The plan shows an ExpressRoute port and a circuit on the port. Apply only if you have ordered fibre at that location.

   ```bash
   terraform plan -out=direct.tfplan
   ```

   Expect: A port with bandwidth 10 or 100 Gbps and encapsulation Dot1Q, and a circuit sized from it.

3. **If you applied: read the status**: `circuitProvisioningState` is Azure's view. `serviceProviderProvisioningState` is the provider's view and must reach `Provisioned`.

   ```bash
   ./scripts/er-check.sh circuit
   ```

   Expect: State `Enabled`, provider state `NotProvisioned` until the provider acts, then `Provisioned`. The service key is shown once for the provider.

4. **Read the port, if any**

   ```bash
   ./scripts/er-check.sh direct
   ```

   Expect: Port bandwidth, encapsulation, the two links and their admin state.

5. **Checkpoint**: A circuit shows Enabled but the provider state is NotProvisioned. Is it usable? Answer: no. The circuit exists but the provider has not connected it, so no BGP session can come up.

## Activity 5: Connect the gateway, set FastPath, and verify the data path

**Goal.** Open gate 3, set `enable_fastpath`, and use read-only commands and metrics to see whether FastPath is applied.

**Exam skill:** Know that FastPath is a property of the connection and is proved with metrics and latency, not with the flag alone.

1. **Plan the connection**: Needs gate 1 and a circuit id: either gate 2 or `existing_circuit_id`. Set `circuit_provisioned_confirmed = true` only after the provider state is Provisioned.

   ```bash
   terraform plan -out=conn.tfplan
   ```

   Expect: A connection of type ExpressRoute with `express_route_gateway_bypass = false`. If you have no circuit, stop at the plan.

2. **Turn FastPath on**: Set `enable_fastpath = true` and plan again. Check that the SKU is one the current docs list as eligible.

   ```bash
   terraform plan -out=fp.tfplan
   terraform apply fp.tfplan
   ```

   Expect: An in-place change to the connection.

3. **Read the flag**

   ```bash
   ./scripts/er-check.sh connection
   ```

   Expect: `expressRouteGatewayBypass: true`. That proves the setting, not the bypass.

4. **Read the BGP state**

   ```bash
   ./scripts/er-check.sh arp
   ./scripts/er-check.sh summary
   ```

   Expect: ARP entries for both ends and a route table summary with learned prefixes on each path.

5. **Prove the bypass**: Send traffic from on-premises to the VM and watch the gateway's packets per second.

   ```bash
   ./scripts/er-check.sh pps
   ```

   Expect: With FastPath working, the gateway's packets per second stays low while the circuit carries data. If it climbs, the traffic is still through the gateway.

6. **Checkpoint**: FastPath is true, a VM answers, but the gateway packet rate rises with the traffic. Name three causes. Answer: an ineligible SKU or circuit, an unsupported destination (Basic load balancer, private endpoint, peered or UDR case), or the route was learned before the flag changed (check current docs).

## Activity 6: Add Global Reach and check the range

**Goal.** Plan a Global Reach connection between two circuits and use the overlap check before you enable it.

**Exam skill:** Know the /29 rule, that Global Reach is configured from one circuit and names the other, and what an overlap looks like.

1. **Check the range first**

   ```bash
   python3 scripts/er-tools.py overlap 192.0.2.8/29 172.16.10.0/24 172.16.20.0/24
   ```

   Expect: `OK`. Do not continue if you see `OVERLAP`.

2. **Set the variables**: Gate 5 needs two private peering ids and the /29. They are inputs, because this lab does not create two circuits.

   ```bash
   terraform plan -out=gr.tfplan -var deploy_global_reach=true
   ```

   Expect: One circuit connection with address_prefix_ipv4 `192.0.2.8/29`. Without real peering ids the plan fails validation, which is the safe outcome.

3. **If applied: read it**

   ```bash
   ./scripts/er-check.sh globalreach
   ```

   Expect: A connection with status `Connected` on both circuits.

4. **Checkpoint**: Two sites, two circuits, Global Reach connected, but site A cannot reach site B. Name one likely cause. Answer: an overlap between the /29 or a site prefix and another advertised range, or a missing route on one circuit's private peering.

## Activity 7: Break/fix drills from captured outputs

**Goal.** Diagnose four broken setups from saved command outputs, offline, using a small triage script.

**Exam skill:** Practise the diagnosis path: circuit state, ARP, BGP on each link, routes, gateway, FastPath.

1. **List the cases**

   ```bash
   ls scripts/fixtures/
   ```

   Expect: Four JSON files: fastpath-gateway, bgp-one-link, globalreach-overlap and gateway-cpu.

2. **Run the first case**: Read the symptom printed at the top, then decide what you would check before you read the diagnosis.

   ```bash
   python3 scripts/er-tools.py triage scripts/fixtures/fastpath-gateway.json
   ```

   Expect: A symptom and a diagnosis: FastPath is true on the connection, but the destination is behind a Basic load balancer.

3. **Run the other three**

   ```bash
   python3 scripts/er-tools.py triage scripts/fixtures/bgp-one-link.json
   python3 scripts/er-tools.py triage scripts/fixtures/globalreach-overlap.json
   python3 scripts/er-tools.py triage scripts/fixtures/gateway-cpu.json
   ```

   Expect: One link with BGP Idle and ARP up; an overlap; and a gateway at 94 percent CPU with a low bandwidth.

4. **Checkpoint**: Which fixture shows a healthy ARP but a failed BGP, and what does that prove? Answer: bgp-one-link. Layer 2 works, so the fault is in BGP: ASN, the /30, the MD5 key, or a filter.

## Activity 8: Collect the evidence and clean up

**Goal.** Gather the evidence for each claim in the guide, then destroy everything the lab created.

**Exam skill:** Know what you destroy, in which order, and that circuits and Direct ports bill until deleted.

1. **Collect the evidence**

   ```bash
   ./scripts/er-check.sh gateway
   ./scripts/er-check.sh effective
   ./scripts/er-check.sh cpu
   ```

   Expect: Save the three outputs next to your notes.

2. **Turn gates off in reverse**: Set the gates back to false in the order 5, 3, 2 or 4, 7, 6, 1, applying after each. Delete a Global Reach connection before the circuits, and a connection before the gateway.

   ```bash
   terraform plan -out=down.tfplan
   terraform apply down.tfplan
   ```

   Expect: Resources are removed. A provider-provisioned circuit may need the provider to deprovision it first (check your contract).

3. **Confirm nothing is left**

   ```bash
   az resource list -g er34-rg -o table
   ```

   Expect: An empty list or only the free baseline.

4. **Destroy the baseline**

   ```bash
   terraform destroy
   ```

   Expect: Everything Terraform created is removed.

5. **Checkpoint**: Why delete the connection before the gateway? Answer: a gateway that still has a connection cannot be deleted, and a deleted gateway leaves the circuit connection dangling.
