# Lab guide: BGP path selection and selective routing

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses are RFC 1918 or RFC 5737 examples. Attribute behaviour of Azure services changes: check current Microsoft docs and record what you observe.

## Activity 1: Plan the free baseline and read the route table

**Goal.** Create the free network objects and read the subnets and the route table that later activities change.

**Exam skill:** Know that Route Server needs a subnet named RouteServerSubnet, that a route table has a BGP route propagation setting, and that every billable object sits behind a gate.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   bash tests/check-gates.sh
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: `OK: all gates default to false`. The plan adds the resource group, the VNet, four subnets, a route table and its association. No Route Server, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. Nothing here bills by the hour.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. `route_server_name` is empty and `nva_public_ips` is an empty map.

3. **Read the subnets**

   ```bash
   az network vnet subnet list -g bgp37-rg --vnet-name bgp37-hub --query "[].{name:name, prefix:addressPrefix}" -o table
   ```

   Expect: `RouteServerSubnet 10.37.0.0/27`, `snet-nva 10.37.1.0/24`, `snet-app 10.37.2.0/24` and `GatewaySubnet 10.37.255.0/27`.

4. **Read the route table**

   ```bash
   az network route-table show -g bgp37-rg -n bgp37-app-rt --query "{propagation:disableBgpRoutePropagation, routes:routes}" -o json
   ```

   Expect: `disableBgpRoutePropagation` is `false` (propagation is on) and the route list is empty.

5. **Checkpoint**: Why must the subnet be named exactly `RouteServerSubnet`, and what may be attached to it? Answer: Route Server looks for that name and nothing else may live there; do not attach a UDR or NSG to it unless current docs allow (they have limits). A /27 or larger is the usual size; check current docs.

## Activity 2: Create Route Server and read its peering details

**Goal.** Open gate 1 and read the Route Server ASN and its two peer addresses, which every NVA must use.

**Exam skill:** Know that Route Server uses ASN 65515, has two instances and therefore two peer IPs, only speaks eBGP, and does not carry data traffic.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_route_server = true`. Leave `branch_to_branch = false` for now.

   ```bash
   terraform plan -out=rs.tfplan
   terraform apply rs.tfplan
   ```

   Expect: A Standard public IP and the Route Server. Creation can take several minutes. Output `route_server_asn` is `65515` and `route_server_ips` lists two addresses in 10.37.0.0/27 (for example 10.37.0.4 and 10.37.0.5).

2. **Read the service**

   ```bash
   az network routeserver show -g bgp37-rg -n bgp37-rs --query "{asn:virtualRouterAsn, ips:virtualRouterIps, b2b:allowBranchToBranchTraffic, state:provisioningState}" -o json
   ```

   Expect: ASN `65515`, two IPs, `b2b` false, state `Succeeded`.

3. **List the peerings**

   ```bash
   ./scripts/bgp-check.sh rs-peers
   ```

   Expect: Empty: no NVA is configured yet.

4. **Checkpoint**: Why does an NVA need to peer with both Route Server addresses? Answer: Route Server runs as two instances for resilience; peering with only one loses the routes when that instance is serviced.

## Activity 3: Bring up two FRR NVAs and read what Route Server learned

**Goal.** Open gate 2, wait for FRR to start on both NVAs, and see the same prefix arrive from two peers and appear on vm-app.

**Exam skill:** Read a BGP session on the NVA, the learned routes on Route Server and the effective routes on a NIC; know that the NVA must use eBGP multihop.

1. **Open gate 2**: Set `deploy_nvas = true` and paste your public key text into `admin_ssh_public_key`. The NVAs need the Route Server addresses, so gate 1 must be applied first.

   ```bash
   terraform plan -out=nva.tfplan
   terraform apply nva.tfplan
   ```

   Expect: Two Route Server peerings (`nva-a` ASN 65001, `nva-b` ASN 65002), two VMs with public IPs for outbound only, vm-app 10.37.2.4.

2. **Check FRR on nva-a**: The boot script installs packages, so wait a few minutes after the VM runs.

   ```bash
   ./scripts/bgp-check.sh nva nva-a
   ```

   Expect: Both neighbours (the two Route Server IPs) `Established`. The table shows 10.99.0.0/24 as local and the VNet prefix 10.37.0.0/16 learned from AS 65515.

3. **Read the learned routes**

   ```bash
   ./scripts/bgp-check.sh rs-peers
   ./scripts/bgp-check.sh rs-learned nva-a
   ./scripts/bgp-check.sh rs-learned nva-b
   ```

   Expect: `10.99.0.0/24` from each peer, with AS path `65001` and `65002`, next hop `10.37.1.4` and `10.37.1.5`.

4. **Read vm-app's effective routes**

   ```bash
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: `10.99.0.0/24` twice, next hop type `VirtualNetworkGateway` (Route Server routes are shown with that source), next hops 10.37.1.4 and 10.37.1.5; besides `10.37.0.0/16` VnetLocal and `0.0.0.0/0` Internet. Two equal entries mean ECMP.

5. **Checkpoint**: Which attribute made the two routes equal? Answer: AS path length (one hop each) with no other difference the service honours. Why is `Established` not enough? Because a session can be up with zero accepted routes (a loop check or filter).

## Activity 4: Steer with AS-path prepend

**Goal.** Make nva-a look longer and watch the effective routes of vm-app move to nva-b.

**Exam skill:** Know that AS-path length is the attribute Azure services reliably see, that you apply it on the sender, and that the other path stays as a backup.

1. **Prepend on nva-a**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters prepend=3
   ```

   Expect: FRR restarts and the session returns to Established within about a minute.

2. **Read what Route Server learned**

   ```bash
   ./scripts/bgp-check.sh rs-learned nva-a
   ```

   Expect: AS path `65001 65001 65001 65001` (four hops).

3. **Read vm-app's effective routes**: Allow a minute for the change to be programmed.

   ```bash
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: One `10.99.0.0/24` route with next hop `10.37.1.4` replaced by `10.37.1.5` (nva-b). Check current Microsoft docs on whether Route Server keeps the longer path in the table.

4. **Fail over on purpose**: Stop FRR on nva-b, wait for the session to drop, then read the routes again.

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts "systemctl stop frr" --query "value[0].message" -o tsv
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: After the hold time (up to about three minutes) nva-a's route is back. This is the backup behaviour.

5. **Restore**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts "systemctl start frr" --query "value[0].message" -o tsv
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   ```

   Expect: Both NVAs announce equally again.

6. **Checkpoint**: Why did the failover take minutes and not seconds? Answer: Route Server waits for the hold timer; the default timers are slow and BFD is not assumed. Check current docs for the timers.

## Activity 5: Local preference, MED and weight: what the service ignores

**Goal.** Apply local preference and MED on the NVAs and observe which of them change Azure's choice.

**Exam skill:** Know that local preference does not cross an eBGP border, that MED is a hint to be verified per service, and why testing beats assuming.

1. **Set local preference 50 on nva-a**: FRR applies it to routes received from Route Server, so it only changes nva-a's own view.

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters localpref=50
   ```

   Expect: On nva-a, `show ip bgp` marks the Route Server routes with LocPrf 50. Nothing changes in Azure.

2. **Confirm Azure did not move**

   ```bash
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: Still two equal `10.99.0.0/24` routes.

3. **Set MED 50 on nva-a and 10 on nva-b**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters med=50
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters med=10
   ```

   Expect: `rs-learned` may show a metric column. Whether Route Server uses MED to choose is for you to observe: record what you see and compare with current Microsoft docs.

4. **Observe and record**

   ```bash
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: Write down whether one or two next hops remain. Do not rely on MED in a design until the service documents it.

5. **Reset**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   ```

   Expect: Baseline restored.

6. **Checkpoint**: Where would local preference matter in a hybrid design? Answer: between two routes your own routers learn inside your AS (iBGP), or inside a service that documents honouring it. It is not a lever for steering Azure from outside.

## Activity 6: Communities, prefix lists and summaries

**Goal.** Tag routes with a community, filter an announcement with a prefix list, and compare a summary with specifics.

**Exam skill:** Choose between a summary and specifics, know that a filter belongs on the sender, and check whether a community survives a service.

1. **Add a community on nva-a**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters community=65001:100
   ```

   Expect: `rs-learned nva-a` and `show ip bgp 10.99.0.0/24` on nva-a show community `65001:100` leaving. Check current docs for whether Route Server passes communities on.

2. **Announce a /24 and a /25, then filter**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters "announce=10.99.0.0/24 10.99.0.0/25" "filter=10.99.0.0/24"
   ```

   Expect: The /25 is originated by FRR but blocked by the outbound prefix list. `rs-learned nva-a` shows only the /24.

3. **Remove the filter**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters "filter="
   ```

   Expect: The /25 now appears in `rs-learned nva-a`, and `app-routes` shows it: nva-a takes half the range because it is longer.

4. **Replace specifics with a summary**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters "announce=10.99.0.0/24 10.99.1.0/24" aggregate=10.99.0.0/16
   ```

   Expect: Only 10.99.0.0/16 is advertised (summary-only hides the two /24s). `app-routes` shows one /16 from nva-a next to the /24 from nva-b; for 10.99.0.9 the /24 still wins by length.

5. **Reset**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   ```

   Expect: Baseline restored.

6. **Checkpoint**: Why does a /16 from nva-a not take traffic from nva-b's /24? Answer: longest prefix match; the summary is only a fallback for addresses the /24 does not cover.

## Activity 7: Propagation toggle, None blackhole and branch-to-branch

**Goal.** Control what a subnet accepts with the route table, and (optionally) see Route Server and a VPN gateway exchange routes.

**Exam skill:** Know the three subnet-level controls (propagation toggle, UDR, None) and the Route Server branch-to-branch setting, and their side effects.

1. **Switch propagation off**: In `terraform.tfvars` set `app_bgp_route_propagation = false`.

   ```bash
   terraform plan -out=prop.tfplan
   terraform apply prop.tfplan
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: `10.99.0.0/24` has disappeared from vm-app's effective routes while `rs-learned` still shows it. Only the VNet range and `0.0.0.0/0` remain.

2. **Switch it back and add a None route**: Set `app_bgp_route_propagation = true` and `blackhole_prefix = "10.99.0.0/24"`.

   ```bash
   terraform plan -out=none.tfplan
   terraform apply none.tfplan
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: A user route `10.99.0.0/24` with next hop `None` appears. For the same prefix, the user route wins over the BGP routes, so packets to 10.99.0.9 are dropped.

3. **Remove the None route**: Set `blackhole_prefix = ""` again and apply.

   ```bash
   terraform apply
   ```

   Expect: The two BGP routes return.

4. **Optional: open gate 3**: Set `deploy_vpn_gateway = true` and apply. This is billable and slow (30 to 45 minutes or more).

   ```bash
   terraform plan -out=gw.tfplan
   terraform apply gw.tfplan
   ```

   Expect: A VPN gateway in GatewaySubnet with BGP enabled, ASN 65010.

5. **Optional: turn branch-to-branch on**: Set `branch_to_branch = true` and apply, then read the gateway.

   ```bash
   terraform apply
   ./scripts/bgp-check.sh gw-learned
   ./scripts/bgp-check.sh gw-peers
   ```

   Expect: With the setting on, the gateway and Route Server exchange routes; the gateway's learned routes can include `10.99.0.0/24`. Exact output depends on the service; check current docs. There is no tunnel peer in this lab, so no on-premises route appears.

6. **Checkpoint**: What is the difference between turning propagation off and adding a None route? Answer: propagation off removes all BGP routes from that subnet's table; None blackholes one prefix and keeps the rest.

## Activity 8: Break and fix, then clean up

**Goal.** Reproduce the symptoms of the break/fix cases on purpose, find them with the verification commands, and tear down.

**Exam skill:** Run the diagnosis path: session, learned routes, effective routes, winner.

1. **Leftover /25 (case 2)**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters "announce=10.99.0.0/24 10.99.0.0/25"
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: A third route, `10.99.0.0/25` via nva-b. Fix: `reset`.

2. **Local preference that does nothing (case 1)**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters localpref=400
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: Still two equal routes. Fix: use prepend. Then reset.

3. **ASN collision (case 3)**: Set `nva_b_asn = 65515` and apply. The peering may be refused at creation because 65515 is reserved; record the error text.

   ```bash
   terraform plan -out=asn.tfplan
   terraform apply asn.tfplan
   ```

   Expect: An error or a session that never establishes. Restore `65002`. Changing the ASN also changes the boot script, so nva-b is replaced.

4. **Propagation off (case 4)**: Repeat Activity 7 step 1 and diagnose it without looking at the answer.

   ```bash
   ./scripts/bgp-check.sh rs-learned nva-a
   ./scripts/bgp-check.sh app-routes
   ```

   Expect: Learned but not on the NIC.

5. **Reset everything**

   ```bash
   az vm run-command invoke -g bgp37-rg -n nva-a --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   az vm run-command invoke -g bgp37-rg -n nva-b --command-id RunShellScript --scripts @scripts/frr-policy.sh --query "value[0].message" -o tsv --parameters reset
   ```

   Expect: Baseline restored.

6. **Destroy the lab**: Set every gate back to `false` and apply, or destroy through your own workflow. The Route Server and any gateway bill until then.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: Everything Terraform created is removed.
