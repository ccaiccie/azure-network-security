# Lab guide: Virtual WAN site-to-site and ExpressRoute routing

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses in the expected output are RFC 1918 and RFC 5737 examples; yours will differ. Check current Microsoft docs for features, limits, prices, CLI flags and provider attribute names. The simulated branch is a VM running strongSwan and FRR: package names and syntax must also be checked. Virtual hubs and gateways bill by the hour: open each gate late and close it early.

## Activity 1: Plan the free baseline

**Goal.** Create only the free objects (the Virtual WAN and four spoke VNets) and see what a WAN is before any hub exists.

**Exam skill:** Know that the WAN object and VNets are free, that a hub is what bills, and that Standard is a property of the WAN.

1. **Prepare the inputs and format the code**: From the `terraform` folder copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 10 objects: 1 resource group, 1 Virtual WAN, 4 VNets and 4 subnets. No hub, no gateway, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. Output `hub1_id` is empty and `route_table_ids_hub1` is an empty map.

3. **Read the WAN**

   ```bash
   az network vwan show -g vwan32-rg -n vwan32-wan --query "{type:type, branchToBranch:allowBranchToBranchTraffic, hubs:virtualHubs}" -o json
   ```

   Expect: type `Standard`, branch-to-branch `true`, no hubs yet.

4. **Checkpoint**: Why is the WAN free and a hub not? Answer: the WAN is a grouping and policy object; the hub runs a managed router and gateways in a region, which is billed. Check current pricing.

## Activity 2: Create hub1, the tables and the spokes

**Goal.** Open gate 1 and gate 2 so hub1 has its route tables and three VNet connections, then prove which spokes reach which with pings.

**Exam skill:** Read a connection's associated table and propagated tables, and predict reachability from them.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_hub1 = true`. The plan shows the hub, two custom tables and three connections.

   ```bash
   terraform plan -out=hub1.tfplan
   terraform apply hub1.tfplan
   ```

   Expect: A hub takes time to create; the router and its default and none tables appear with it. Output `hub1_router_ips` lists two addresses in 10.100.0.0/24.

2. **Open gate 2**: Set `deploy_vms = true` and paste your public key text into `admin_ssh_public_key`.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: Four VM NICs and three VMs (eu2 comes with gate 5). No public IPs.

3. **List the route tables**

   ```bash
   ./scripts/vwan-check.sh tables
   ```

   Expect: Names `defaultRouteTable`, `noneRouteTable`, `rt-spokes`, `rt-branch` with their labels.

4. **Predict, then test**: Write down what you expect, using the table plan in the guide. Then run the pings from prod.

   ```bash
   ./scripts/vwan-check.sh ping vm-prod 10.103.0.4
   ./scripts/vwan-check.sh ping vm-prod 10.102.0.4
   ./scripts/vwan-check.sh ping vm-shared 10.102.0.4
   ```

   Expect: prod to shared: replies. prod to dev: 100 percent loss (rt-spokes has no dev route). shared to dev: replies (Default has dev).

5. **Read the NIC routes**

   ```bash
   ./scripts/vwan-check.sh nic prod
   ```

   Expect: A route for 10.103.0.0/24 with next hop type Virtual network gateway, and none for 10.102.0.0/24. Source `VirtualNetworkGateway`.

6. **Checkpoint**: Which setting makes prod unable to reach dev? Answer: association. prod reads rt-spokes, and dev never writes into rt-spokes. Route propagation by dev to Default only helps connections that read Default.

## Activity 3: Association, propagation and labels

**Goal.** Read effective routes of tables and connections until you can say who reads and who writes, and add the two kinds of static route.

**Exam skill:** Tell association from propagation, read hub and connection effective routes, and place a static route in a table or on a connection.

1. **Read each table**

   ```bash
   ./scripts/vwan-check.sh routes defaultRouteTable
   ./scripts/vwan-check.sh routes rt-spokes
   ./scripts/vwan-check.sh routes rt-branch
   ```

   Expect: Default holds prod, dev and shared (and the branch once Activity 4 is done); rt-spokes holds shared only for now; rt-branch holds prod and shared.

2. **Read a connection**: The connection's effective routes are what it learned through its association.

   ```bash
   ./scripts/vwan-check.sh conn conn-prod
   ```

   Expect: Routes taken from rt-spokes: 10.103.0.0/24 and nothing else.

3. **Turn on the static routes**: Set `static_routes = true`. A row in rt-spokes sends 10.251.0.0/24 to conn-shared, and the shared connection gets a static route 10.250.0.0/24 via 10.103.0.10.

   ```bash
   terraform plan -out=static.tfplan
   terraform apply static.tfplan
   ```

   Expect: Two new rows. Check current docs for how static routes on a connection are propagated.

4. **Read the tables again**

   ```bash
   ./scripts/vwan-check.sh routes rt-spokes
   ./scripts/vwan-check.sh routes defaultRouteTable
   ```

   Expect: rt-spokes now lists 10.251.0.0/24 with next hop conn-shared. Default lists 10.250.0.0/24 via the shared connection (static).

5. **Checkpoint**: A static route in a table and a static route on a connection: where does each point? Answer: a table row points at a connection (an NVA or firewall connection) for the readers of that table; a connection route names an IP in that VNet, and can be propagated to the tables the connection writes into. Neither has any liveness check.

## Activity 4: Connect the branch with S2S VPN and BGP

**Goal.** Open gates 3 and 4 so the simulated branch peers with the hub, and check what each side learns and why dev is hidden.

**Exam skill:** Read BGP state on both sides, understand that the branch's association decides what it learns, and test reachability both ways.

1. **Open gate 3**: Set `deploy_branch_sim = true`. vm-edge installs strongSwan and FRR at boot.

   ```bash
   terraform plan -out=branch.tfplan
   terraform apply branch.tfplan
   ```

   Expect: Branch VNet, NSG for UDP 500 and 4500, route table on snet-lan, two VMs. Output `edge_public_ip` shows the address.

2. **Open gate 4**: Set `deploy_vpn = true` and a lab-only `shared_key` of 16 or more characters. Creating the gateway takes a while.

   ```bash
   terraform plan -out=vpn.tfplan
   terraform apply vpn.tfplan
   ```

   Expect: VPN gateway with two instances, a VPN site with BGP ASN 65020, a connection with association rt-branch. Output `vpn_gateway_bgp_ips` shows two addresses.

3. **Check the device**: Wait a few minutes after the VM shows as running.

   ```bash
   ./scripts/vwan-check.sh device
   ```

   Expect: Two `ESTABLISHED` IKE SAs and BGP neighbors `Established` with ASN 65515. Prefixes received include 10.101.0.0/24 and 10.103.0.0/24 and not 10.102.0.0/24.

4. **Read the hub side**

   ```bash
   ./scripts/vwan-check.sh routes defaultRouteTable
   ./scripts/vwan-check.sh routes rt-spokes
   ```

   Expect: Both now list 10.80.0.0/24 and 10.80.2.0/24 with the branch connection as next hop.

5. **Test the paths**

   ```bash
   az vm run-command invoke -g vwan32-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 3 10.101.0.4; ping -c 3 -W 2 10.102.0.4" --query "value[0].message" -o tsv
   ./scripts/vwan-check.sh ping vm-prod 10.80.2.10
   ```

   Expect: vm-lan to prod replies; vm-lan to dev gets no reply (dev is not in rt-branch). prod to vm-lan replies.

6. **Checkpoint**: What decides that the branch does not learn dev? Answer: the branch connection's association (rt-branch), which has no dev row because dev propagates only to Default.

## Activity 5: Peer an NVA with the hub router

**Goal.** Open gate 7 so vm-nva in the shared spoke exchanges routes with the hub router by BGP, and see the prefix appear in the tables.

**Exam skill:** Know that the hub router has two instances, ASN 65515, that the NVA must peer with both and use multihop, and that the learned route appears like any other.

1. **Open gate 7**: Needs gates 1 and 2. Set `deploy_nva_bgp = true`.

   ```bash
   terraform plan -out=nva.tfplan
   terraform apply nva.tfplan
   ```

   Expect: vm-nva (10.103.0.10, forwarding on) and a hub BGP connection `bgp-nva` with peer ASN 65030.

2. **Check the NVA**

   ```bash
   az vm run-command invoke -g vwan32-rg -n vm-nva --command-id RunShellScript --scripts "vtysh -c 'show ip bgp summary'" --query "value[0].message" -o tsv
   ```

   Expect: Two neighbors (the hub router IPs) in state `Established`, and one prefix sent: 10.250.0.0/24.

3. **Read the hub**: Compare with the static version from Activity 3.

   ```bash
   ./scripts/vwan-check.sh routes defaultRouteTable
   ```

   Expect: 10.250.0.0/24 is present with the NVA as next hop; it was learned dynamically, so it leaves if the session drops.

4. **Break it on purpose**: Stop FRR on the NVA, wait for the hold timer, and read the table again.

   ```bash
   az vm run-command invoke -g vwan32-rg -n vm-nva --command-id RunShellScript --scripts "systemctl stop frr" --query "value[0].message" -o tsv
   ./scripts/vwan-check.sh routes defaultRouteTable
   ```

   Expect: After the BGP hold time the dynamic route disappears. A static route for the same prefix (Activity 3) would still be there.

5. **Checkpoint**: Why must the NVA peer with both router IPs? Answer: the hub router is two instances; a session with only one loses routes when that instance is updated. Check current docs for the exact multihop and ASN rules.

## Activity 6: Add hub2 and watch hub-to-hub and labels

**Goal.** Open gate 5 so a second hub joins the WAN, and prove that labels carry prefixes into the right tables of the other hub.

**Exam skill:** Explain hub-to-hub transit, why a label only works when a table in the other hub carries it, and where the hub-to-hub path shows in effective routes.

1. **Open gate 5**: Set `deploy_hub2 = true`. Hub2 has its own default table plus rt-spokes and rt-branch (empty but labelled), and the eu2 connection.

   ```bash
   terraform plan -out=hub2.tfplan
   terraform apply hub2.tfplan
   ```

   Expect: Hub2, two tables, one connection, and vm-eu2 (if gate 2 is open).

2. **Read hub1's tables**: Use the hub name `vwan32-hub1`. 10.201.0.0/24 should now be in Default, rt-spokes and rt-branch of hub1.

   ```bash
   ./scripts/vwan-check.sh routes rt-branch
   ```

   Expect: 10.201.0.0/24 with next hop `vwan32-hub2` (hub-to-hub). It arrived through the labels default, spokes and branch.

3. **Test the paths**

   ```bash
   ./scripts/vwan-check.sh ping vm-prod 10.201.0.4
   ./scripts/vwan-check.sh ping vm-eu2 10.101.0.4
   ./scripts/vwan-check.sh ping vm-eu2 10.102.0.4
   ```

   Expect: prod and eu2 reach each other. eu2 also reaches dev, because eu2 reads hub2's Default, which received dev through the label default.

4. **Read hub2**: Point the helper at hub2.

   ```bash
   HUB=vwan32-hub2 ./scripts/vwan-check.sh routes defaultRouteTable
   ```

   Expect: Hub1's prefixes, including the branch's 10.80.x, with next hop hub1. The path carries a hub-to-hub AS path; check current docs for the exact number.

5. **Checkpoint**: Why does eu2 reach dev while prod cannot? Answer: reachability is per reader. eu2 reads Default of hub2, which holds everything labelled default. prod reads rt-spokes, which dev never writes into. If you want eu2 to be as isolated as prod, change its association.

## Activity 7: ExpressRoute gateway, coexistence and preference

**Goal.** Open gate 6 to see where ExpressRoute plugs in, and change the hub routing preference to see how the plan reads. A circuit is optional.

**Exam skill:** Say which path a hub prefers for the same prefix, how the preference setting changes it, and where Global Reach fits.

1. **Open gate 6**: An ER gateway bills by scale unit even without a circuit. Open it only when you want to read it.

   ```bash
   terraform plan -out=er.tfplan
   terraform apply er.tfplan
   ```

   Expect: One ER gateway in hub1. No ExpressRoute connection exists unless `er_circuit_peering_id` is set.

2. **Read the preference**

   ```bash
   az network vhub show -g vwan32-rg -n vwan32-hub1 --query "{pref:routingPreference, asn:virtualRouterAsn, ips:virtualRouterIps}" -o json
   ```

   Expect: pref `ExpressRoute` (the default), asn 65515, two router IPs.

3. **Change the preference in the plan**: Set `hub_routing_preference = "ASPath"` and run only a plan. Read the in-place change, then set it back unless you want to apply.

   ```bash
   terraform plan
   ```

   Expect: One in-place update on `azurerm_virtual_hub.hub1`. Accepted values and behaviour: check current docs.

4. **Optional: with a circuit**: If you already own a circuit, set `er_circuit_peering_id` and apply. Then read the effective routes for a branch prefix that arrives by both ER and VPN.

   ```bash
   ./scripts/vwan-check.sh routes rt-branch
   ```

   Expect: With ExpressRoute preferred, the ER path is the one used; the VPN stays as backup. Global Reach is configured on the circuits, not in this lab.

5. **Checkpoint**: If the same prefix arrives by ER and by VPN, which does the hub use by default and what changes it? Answer: ExpressRoute, and the hub routing preference (ExpressRoute, VPN or AS path). Check current docs.

## Activity 8: Break/fix drills and clean-up

**Goal.** Inject each fault with one switch, find it with effective routes, and fix it. Then destroy the lab in a safe order.

**Exam skill:** Follow the path: NIC route, connection, association, propagation, label.

1. **Fault A: a label typo**: Set `fault = "label_typo"` and apply. conn-prod now propagates to the label `brnach`.

   ```bash
   terraform apply
   ./scripts/vwan-check.sh routes rt-branch
   az vm run-command invoke -g vwan32-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 2 -W 2 10.101.0.4" --query "value[0].message" -o tsv
   ```

   Expect: rt-branch has no 10.101.0.0/24 row, and vm-lan cannot reach prod. Fix: set the fault back to `none`.

2. **Fault B: shared writes to None**: Set `fault = "shared_none"` and apply.

   ```bash
   terraform apply
   ./scripts/vwan-check.sh routes rt-spokes
   ./scripts/vwan-check.sh ping vm-prod 10.103.0.4
   ```

   Expect: rt-spokes lost 10.103.0.0/24 and prod can no longer reach shared. Fix: set the fault back to `none`.

3. **Fault C: the branch reads Default**: Set `fault = "branch_assoc_default"` and apply. Then look at what the branch learned.

   ```bash
   terraform apply
   ./scripts/vwan-check.sh device
   ```

   Expect: The device receives 10.102.0.0/24 as well, plus more. Fix: set the fault back to `none`.

4. **Fault D: asymmetric hub-to-hub**: Cannot be reproduced without a second branch connection. Read the case in the guide and draw both directions on paper using the effective routes of both hubs.

   Expect: Your drawing should show the forward path through hub1 and the reply through hub2.

5. **Clean up**: Set every gate to `false` and apply, or destroy. Hubs delete last because gateways and connections must go first. Check the portal for leftover hubs or gateways.

   ```bash
   terraform destroy
   ```

   Expect: Resource group gone. Confirm with `az group exists -n vwan32-rg` returns false.
