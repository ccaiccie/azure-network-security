# Lab guide: capstone multi-region reference skeleton

This is a **reference skeleton**, not a full deployment. Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses are RFC 1918 or RFC 5737 examples. Check current Microsoft docs and the provider docs before you apply anything.

## Activity 1: Check the gates and create the two regions

**Goal.** Confirm that every gate is closed by default, open gates 1 and 2, and read the address plan the skeleton produces.

**Exam skill:** Know the address plan of both regions, that the hub and spokes are separate VNets, and why every billable stage sits behind a gate.

1. **Prepare inputs and run the static checks**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   bash tests/check-gates.sh
   bash tests/check-plan-addresses.sh
   ```

   Expect: `OK: all gates default to false` and `OK: 10.20.0.0/15, 10.22.0.0/15 and 10.200.0.0/16 are present and disjoint`. (Designed, not tested.)

2. **Plan with every gate closed**: A plan with all gates false must create nothing.

   ```bash
   terraform init
   terraform plan -out=none.tfplan
   ```

   Expect: `No changes` or an empty plan. If anything is created, a gate default is wrong.

3. **Open gates 1 and 2**: In `terraform.tfvars` set `deploy_region_a = true` and `deploy_region_b = true`, then plan and apply through your approved workflow.

   ```bash
   terraform plan -out=regions.tfplan
   terraform apply regions.tfplan
   ```

   Expect: Two resource groups, two hub VNets with six subnets each, six spoke VNets, route tables and an NSG. No billable resource.

4. **Read the address plan**

   ```bash
   terraform output address_plan
   az network vnet list -g cap36-a-rg --query "[].{name:name, space:addressSpace.addressPrefixes[0]}" -o table
   ```

   Expect: Hub `10.20.0.0/22` and spokes `10.20.4.0/22`, `10.20.8.0/22`, `10.20.16.0/21`; region B uses 10.22.

5. **Checkpoint**: Why is the whole of region A one /15 although only about a /20 is used? Answer: so that one summary route and one firewall rule can cover the region, and so that growth never needs a renumber.

## Activity 2: Peer the hubs and read the route tables

**Goal.** Open gate 3, read the peerings and the four route tables, and predict the effective routes of a web VM on paper.

**Exam skill:** Know that spokes peer only to their hub, that hub peering is not transitive, and which routes each table must contain.

1. **Open gate 3 and apply**: Set `enable_peering = true`, plan, and apply.

   ```bash
   terraform plan -out=peer.tfplan
   terraform apply peer.tfplan
   ```

   Expect: Six hub-to-spoke pairs and the hub-A-to-hub-B pair of peerings.

2. **List the peerings**

   ```bash
   az network vnet peering list -g cap36-a-rg --vnet-name cap36-hub-a --query "[].{name:name, state:peeringState, fwd:allowForwardedTraffic}" -o table
   ```

   Expect: Peerings to web, data and aks spokes, and to hub B, all `Connected`.

3. **Read the spoke route table**

   ```bash
   az network route-table show -g cap36-a-rg -n cap36-rt-spoke-a --query "{prop:disableBgpRoutePropagation, routes:routes[].{n:name,p:addressPrefix,h:nextHopIpAddress}}" -o json
   ```

   Expect: `prop` is `true` (propagation off) and four routes: `0.0.0.0/0`, `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16`, all to 10.20.0.4.

4. **Read the gateway and firewall subnet tables**

   ```bash
   az network route-table show -g cap36-a-rg -n cap36-rt-gw-a --query "routes[].{p:addressPrefix}" -o tsv
   az network route-table show -g cap36-a-rg -n cap36-rt-fw-a --query "routes[].{p:addressPrefix}" -o tsv
   ```

   Expect: Three spoke prefixes on the gateway table; `10.22.0.0/15` on the firewall table.

5. **Predict, then compare**: Write the effective routes you expect on a web VM NIC, then compare with the guide. If you add your own VM through your workflow, run `az network nic show-effective-route-table`. Expect the hub /22 by peering and the UDRs, and no `10.200.0.0/16`.

6. **Checkpoint**: Which route lets fw-a reach spoke B, and why is it needed? Answer: the `10.22.0.0/15` UDR to fw-b; hub peering does not carry the other hub's spokes.

## Activity 3: Add the firewall policy and predict rule hits

**Goal.** Open gate 4, read the base and child policies, and predict the rule that each of the nine flows hits.

**Exam skill:** Know that child policies inherit a base policy, that application rules proxy and change the source, and that unlisted traffic is denied.

1. **Open gate 4 and apply**: Set `deploy_firewall_policy = true`. A policy alone has no firewall, so check current pricing.

   ```bash
   terraform plan -out=pol.tfplan
   terraform apply pol.tfplan
   ```

   Expect: One base policy and one child policy per region, plus the `rcg-base` rule collection group.

2. **Read the policies**

   ```bash
   az network firewall policy show -g cap36-global-rg -n cap36-fwp-base --query "{sku:sku.tier, children:childPolicies[].id}" -o json
   ```

   Expect: SKU `Premium` and two child policies.

3. **Read the rules**

   ```bash
   az network firewall policy rule-collection-group show -g cap36-global-rg --policy-name cap36-fwp-base -n rcg-base --query "ruleCollections[].{n:name, p:priority, a:action.type}" -o table
   ```

   Expect: `net-core` priority 200 and `app-egress` priority 300, both Allow.

4. **Predict the nine flows**: For each flow in the guide, write the rule it hits. Expected: flow 1 `onprem-to-web-https`, flow 3 `web-to-app-8443`, flow 4 `os-updates`, flow 5 no rule (implicit deny), flow 8 `app-to-private-endpoints`.

5. **Optional: open gate 6**: Only with approval. Gate 6 creates two billable Premium firewalls. After it, read the real private addresses.

   ```bash
   terraform output firewall_private_ips
   ```

   Expect: Both addresses should be `.4`; if not, change the route tables before using them.

6. **Checkpoint**: Why does a name-based east-west call arrive with the firewall's source address? Answer: it matched an application rule, which proxies the connection.

## Activity 4: Link the private DNS zone and read the resolver design

**Goal.** Open gate 5, link the zone to both hubs, and see why one missing link breaks one region.

**Exam skill:** Know that private zones must be linked to the VNet that resolves them, that the hub is where the chain resolves, and what the resolver inbound and outbound endpoints do.

1. **Open gate 5 and apply**: Set `link_private_dns = true`.

   ```bash
   terraform plan -out=dns.tfplan
   terraform apply dns.tfplan
   ```

   Expect: One zone, two hub links and one example spoke link.

2. **List the links**

   ```bash
   az network private-dns link vnet list -g cap36-dns-rg -z privatelink.blob.core.windows.net --query "[].{name:name, vnet:virtualNetwork.id}" -o table
   ```

   Expect: `link-hub-a`, `link-hub-b` and `link-spoke-a-web`.

3. **Break it on purpose**: In a scratch copy, remove the `link-hub-b` resource and plan. The plan shows one deletion. Region B would then resolve the storage name to a public address, as in break/fix case 2. Do not apply the broken plan; keep it as a review exercise.

4. **Optional: open gate 7**: Only with approval; resolvers are billable.

   ```bash
   terraform output resolver_inbound_ips
   ```

   Expect: `a = 10.20.1.4` and `b = 10.22.1.4`, the addresses the firewall policy already uses as DNS servers.

5. **Checkpoint**: Why link the zone to the hubs and not to every spoke? Answer: spokes ask the firewall, the firewall asks the hub resolver, and the hub's Azure DNS answers from the linked zone, so one link per hub is enough.

## Activity 5: Simulate on-premises and read BGP routes

**Goal.** Optionally open gates 8 and 9 and read the learned and advertised routes of a gateway with a BGP peer.

**Exam skill:** Know how to read learned and advertised routes, and that ExpressRoute cannot be simulated with a VNet-to-VNet VPN.

1. **Open gate 8**: Set `deploy_onprem_sim = true`. It creates a VNet 10.200.0.0/16 and two subnets and costs nothing.

   ```bash
   terraform plan -out=onp.tfplan
   terraform apply onp.tfplan
   ```

   Expect: A VNet `cap36-onprem` with `snet-dns` and `snet-app`.

2. **Optional: open gate 9**: Only with approval. Gateways are billable and take a long time. Provide the key through an environment variable, never in a file you commit.

   ```bash
   export TF_VAR_vpn_shared_key='<at least 16 characters>'
   terraform plan -out=vpn.tfplan
   terraform apply vpn.tfplan
   ```

   Expect: Two VPN gateways and two connections with BGP.

3. **Read the BGP peer status**

   ```bash
   az network vnet-gateway list-bgp-peer-status -g cap36-a-rg -n cap36-vpngw-a -o table
   ```

   Expect: A peer with ASN 65010 in state `Connected`.

4. **Read learned and advertised routes**

   ```bash
   az network vnet-gateway list-learned-routes -g cap36-a-rg -n cap36-vpngw-a -o table
   az network vnet-gateway list-advertised-routes -g cap36-a-rg -n cap36-vpngw-a --peer 10.200.255.4 -o table
   ```

   Expect: Learned: `10.200.0.0/16` from the peer. Advertised: the hub A and peered spoke prefixes. The peer address depends on the gateway; read it from the peer status.

5. **Checkpoint**: Why does the skeleton not simulate ExpressRoute? Answer: a circuit needs a provider and a peering location, so the ExpressRoute behaviour in this design is studied on paper, in the flow maps and in the failure analysis.
