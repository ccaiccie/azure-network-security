# Lab guide: VNet addressing, subnets, peering and gateway transit

Run the activities in order from the `terraform` folder. **Every command here is designed, not tested:** nothing has been applied to Azure and the expected outputs are design intent. Free by default: virtual networks, subnets and peerings. Costly: the VMs (hourly), the VPN gateway (hourly, slow to create) and the public IP behind it. All costly parts are behind gates that default to false.

All commands assume `export RG=vnet-peering-lab` and a key at `~/.ssh/id_ed25519.pub`. Replace both to suit you. The variables `-var admin_ssh_public_key=...` are written out in each command so that every apply names the full state it expects.

## Activity 1: Address plan, reserved addresses and the free substrate

**Goal.** Build the three VNets and four subnets (no VMs yet), then read the address plan and prove which addresses Azure reserves.

**Exam skill.** Plan non-overlapping address space, know the five reserved addresses per subnet and the smallest subnet size.

1. **Prepare and check the files (no Azure call)**: From the `terraform` folder. Copy the example variables, put your own subscription id in, then run the local source check.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   python3 -I tests/check_contract.py
   terraform fmt -check -recursive
   terraform init
   terraform validate
   ```

   Expected: `ok: 7 gates default false, 8 peering resources, break_fix defaults to none`, then `Success! The configuration is valid.`

2. **Preview the free substrate**: All seven gates are false, so the plan holds only the group, VNets, subnets and the peering links between hub and the two spokes.

   ```bash
   terraform plan -out=tfplan
   ```

   Expected: `Plan: 12 to add, 0 to change, 0 to destroy.` (1 group, 3 VNets, 4 subnets, 4 peering links).

3. **Apply it**: Virtual networks, subnets and peerings have no hourly charge in themselves.

   ```bash
   terraform apply tfplan
   export RG=vnet-peering-lab
   ```

   Expected: `Apply complete! Resources: 12 added`. The `address_plan` output lists the three ranges.

4. **Read the address plan back from Azure**: Compare what Azure holds with what you planned.

   ```bash
   terraform output address_plan
   az network vnet list -g $RG --query "[].{name:name, space:addressSpace.addressPrefixes[0]}" -o table
   ```

   Expected: `vnet-hub 10.0.0.0/16`, `vnet-spoke-a 10.10.0.0/16`, `vnet-spoke-b 10.20.0.0/16`. No two ranges overlap.

5. **Probe the reserved addresses**: Ask Azure whether four addresses of `snet-app` in spoke-a are free to assign.

   ```bash
   for ip in 10.10.1.0 10.10.1.1 10.10.1.3 10.10.1.4; do
     echo "== $ip"
     az network vnet check-ip-address -g $RG -n vnet-spoke-a --ip-address $ip --query available
   done
   ```

   Expected: Expected (designed, not tested): `false` for .0, .1 and .3, and `true` for .4, the first usable address. If a reserved address reports `true`, record the output and check current Microsoft docs.

**Checkpoint questions.**

- Why is 10.10.1.4 the first address a VM can get? *Answer: Azure reserves the network address (.0), the default gateway (.1), two addresses for Azure DNS (.2 and .3) and the broadcast address (the last one).*
- What is the smallest subnet Azure supports, and how many addresses can you use in it? *Answer: A /29: 8 addresses minus 5 reserved leaves 3 (check current docs for the limit).*

**If it doesn't work.** If `plan` asks for a subscription id, you did not edit `terraform.tfvars`. If the check script prints a problem, a gate no longer defaults to false.

## Activity 2: Peering state and the four properties

**Goal.** Read both links of a peering, see the four properties on each, and watch the state change when one side disappears.

**Exam skill.** Know that peering is two one-way links, the meaning of Initiated, Connected and Disconnected, and which side each property lives on.

1. **List the hub's links and their state**: The hub holds two links, one per spoke.

   ```bash
   az network vnet peering list -g $RG --vnet-name vnet-hub -o table
   ```

   Expected: `hub-to-spoke-a` and `hub-to-spoke-b`, both `Connected`.

2. **Print the properties with the helper**: The helper prints state, sync level and the four properties for every link on one VNet.

   ```bash
   ./scripts/diagnose.sh $RG vnet-spoke-a
   ```

   Expected: One row `spoke-a-to-hub`: access True, fwd False, gwt False, rgw False, remote `10.0.0.0/16`. The sync column shows `FullyInSync` (field name and values: check current docs).

3. **Remove one side on purpose**: Apply the `one_sided` switch: Terraform deletes `spoke-b-to-hub` and keeps `hub-to-spoke-b`.

   ```bash
   terraform apply -var break_fix=one_sided
   az network vnet peering list -g $RG --vnet-name vnet-hub --query "[].{name:name, state:peeringState}" -o table
   ```

   Expected: `hub-to-spoke-b` is no longer `Connected`: `Disconnected` after a deletion, or `Initiated` if the link had never been reciprocated.

4. **Restore it**: Put the second link back.

   ```bash
   terraform apply -var break_fix=none
   az network vnet peering list -g $RG --vnet-name vnet-hub --query "[].{name:name, state:peeringState}" -o table
   ```

   Expected: Both links `Connected` again. If one stays `Disconnected`, delete and recreate both links (check current docs).

**Checkpoint questions.**

- Which VNet owns the link named `spoke-a-to-hub`? *Answer: spoke-a. A link lives on the VNet it is named for and describes how that VNet treats the remote one.*
- A link is Initiated. What is missing? *Answer: The reciprocal link on the other VNet.*

**If it doesn't work.** A state that does not become Connected for several minutes means the other link is missing or was created in the wrong direction.

## Activity 3: Effective routes and the proof that peering is not transitive

**Goal.** Deploy three small VMs, read the effective routes of each NIC, and prove that spoke-a cannot reach spoke-b through the hub.

**Exam skill.** Read a spoke's effective route table, recognise the VNetPeering rows and the 10.0.0.0/8 None row, and explain why the hub does not pass traffic on.

1. **Deploy the VMs**: Gate 1. Three Ubuntu VMs with private IPs only: `vm-hub` 10.0.1.4, `vm-a` 10.10.1.4, `vm-b` 10.20.1.4.

   ```bash
   terraform apply -var deploy_vms=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   ```

   Expected: `Apply complete!` with `vm_private_ips` listing the three VMs. The VMs bill hourly until destroyed.

2. **Read vm-a's effective routes**: These are the routes that really apply to the NIC.

   ```bash
   az network nic show-effective-route-table -g $RG -n nic-vm-a -o table
   ```

   Expected: Default routes: `10.10.0.0/16 VnetLocal`, `10.0.0.0/16 VNetPeering`, `0.0.0.0/0 Internet`, and `None` rows for `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`. There is no row for `10.20.0.0/16`. Other None rows may appear.

3. **Ping the hub, then spoke-b**: Run a short ping from inside vm-a with run-command.

   ```bash
   az vm run-command invoke -g $RG -n vm-a --command-id RunShellScript --scripts "ping -c 3 -W 2 10.0.1.4; ping -c 3 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   ```

   Expected: The first ping shows `0% packet loss`. The second shows `100% packet loss`.

4. **Ask Network Watcher for the next hop**: Next hop shows the decision for one destination.

   ```bash
   az network watcher show-next-hop -g $RG --vm vm-a --source-ip 10.10.1.4 --dest-ip 10.20.1.4 -o table
   ```

   Expected: Next hop type `None`, caused by the `10.0.0.0/8` system route. With `--dest-ip 10.0.1.4` the type is the peering type.

5. **Show that the hub itself still reaches both**: The hub has its own link to each spoke.

   ```bash
   az vm run-command invoke -g $RG -n vm-hub --command-id RunShellScript --scripts "ping -c 2 -W 2 10.10.1.4; ping -c 2 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   ```

   Expected: Both succeed. The hub is a neighbour of each spoke, but it does not forward between them.

**Checkpoint questions.**

- Why is the packet to 10.20.1.4 dropped and not sent to the Internet? *Answer: The longest match is the system route 10.0.0.0/8 with next hop None, which beats 0.0.0.0/0.*
- What would add a 10.20.0.0/16 row to vm-a's table? *Answer: A direct peering to spoke-b, or a user route, as the next activity shows.*

**If it doesn't work.** If run-command does not return, the VM agent may still be starting: wait a minute. If `check-ip-address` or ping disagree with the expected output, record what you saw and check current Microsoft docs.

## Activity 4: Two fixes for spoke-to-spoke traffic: direct peering and a forwarding VM

**Goal.** Make vm-a reach vm-b, first with a direct peering, then with a forwarding VM in the hub plus user routes and allow forwarded traffic.

**Exam skill.** Choose between direct peering and a hub appliance, and know that forwarded traffic must be allowed on the receiving side.

1. **Fix 1: peer the spokes directly**: Gate 2 adds `spoke-a-to-spoke-b` and `spoke-b-to-spoke-a`.

   ```bash
   terraform apply -var deploy_vms=true -var peer_spokes_directly=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   az network nic show-effective-route-table -g $RG -n nic-vm-a -o table | grep 10.20
   ```

   Expected: A new `10.20.0.0/16 VNetPeering` row on vm-a.

2. **Test fix 1**: Ping spoke-b from spoke-a.

   ```bash
   az vm run-command invoke -g $RG -n vm-a --command-id RunShellScript --scripts "ping -c 3 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   ```

   Expected: `0% packet loss`. The path is direct: it does not cross the hub.

3. **Switch to fix 2: remove the direct links, add the forwarding VM**: Gate 3 creates `vm-nva` (10.0.2.4) with IP forwarding on the NIC and in the guest, route tables on both spokes and `allow_forwarded_traffic` on the spoke links.

   ```bash
   terraform apply -var deploy_vms=true -var peer_spokes_directly=false -var deploy_nva=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   ```

   Expected: The two direct links are destroyed; `vm-nva`, `rt-spoke-a`, `rt-spoke-b` and two associations are created.

4. **Check the forwarding settings**: Forwarding must be on in two places: the Azure NIC and the guest operating system.

   ```bash
   az network nic show -g $RG -n nic-nva --query enableIPForwarding
   az vm run-command invoke -g $RG -n vm-nva --command-id RunShellScript --scripts "sysctl net.ipv4.ip_forward" --query "value[0].message" -o tsv
   ```

   Expected: `true`, and `net.ipv4.ip_forward = 1`.

5. **Read the new route and test**: vm-a now has a user route for spoke-b's prefix.

   ```bash
   az network nic show-effective-route-table -g $RG -n nic-vm-a -o table | grep 10.20
   az vm run-command invoke -g $RG -n vm-a --command-id RunShellScript --scripts "ping -c 3 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   ```

   Expected: A `User 10.20.0.0/16 VirtualAppliance 10.0.2.4` row, and `0% packet loss`. The path is vm-a, the NVA, vm-b.

**Checkpoint questions.**

- Which spoke link must allow forwarded traffic for the reply from vm-b to vm-a? *Answer: spoke-a-to-hub: the reply arrives at spoke-a from the hub, but its source address belongs to spoke-b.*
- With both fixes on at once, which route wins on vm-a for 10.20.0.0/16? *Answer: The user route to the NVA: equal prefix length, and User beats System.*

**If it doesn't work.** If fix 2 fails, check in this order: the user route in effective routes, NIC forwarding, guest forwarding, then the forwarded-traffic flag on both spoke links.

## Activity 5: Global peering, gateway transit and use remote gateways

**Goal.** Peer a VNet in another region, then (optionally, costly) let spoke-a use the hub's VPN gateway and read the resulting gateway routes.

**Exam skill.** Know what changes with global peering, and where Allow gateway transit and Use remote gateways are set.

1. **Add spoke-c in a second region**: Gate 4 creates `vnet-spoke-c` 10.30.0.0/16 in `secondary_location` and peers it with the hub.

   ```bash
   terraform apply -var deploy_vms=true -var create_global_peering=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   az network vnet peering list -g $RG --vnet-name vnet-hub --query "[].{name:name, state:peeringState}" -o table
   ```

   Expected: `hub-to-spoke-c Connected`. A global peering is created in exactly the same way as a regional one.

2. **Test across regions**: From the hub VM to the VM in the other region.

   ```bash
   az vm run-command invoke -g $RG -n vm-hub --command-id RunShellScript --scripts "ping -c 3 -W 3 10.30.1.4" --query "value[0].message" -o tsv
   ```

   Expected: `0% packet loss`, with a slightly higher round-trip time than in-region.

3. **COSTLY. Create the gateway (30 minutes or more)**: Gates 5 and 6. The hub gets `vpngw-hub` and `GatewaySubnet` 10.0.254.0/27. The hub links offer transit and `spoke-a-to-hub` uses the remote gateway.

   ```bash
   terraform apply -var deploy_vms=true -var create_gateway=true -var enable_gateway_transit=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   ```

   Expected: `vpngw-hub` is created (long wait). Both links are rewritten with the new flags.

4. **Read the flags on each side**: Transit lives on the hub link, remote gateways on the spoke link.

   ```bash
   az network vnet peering show -g $RG --vnet-name vnet-hub -n hub-to-spoke-a --query "{gwt:allowGatewayTransit, rgw:useRemoteGateways}"
   az network vnet peering show -g $RG --vnet-name vnet-spoke-a -n spoke-a-to-hub --query "{gwt:allowGatewayTransit, rgw:useRemoteGateways}"
   ```

   Expected: hub-to-spoke-a: `gwt true, rgw false`. spoke-a-to-hub: `gwt false, rgw true`.

5. **Add a pretend on-premises site (optional)**: Gate 7 creates `lng-onprem` (192.168.100.0/24, gateway address 203.0.113.10) and an IPsec connection. Supply the key through the environment only. No real device exists, so the tunnel will not come up.

   ```bash
   read -s -p 'PSK: ' TF_VAR_vpn_shared_key; export TF_VAR_vpn_shared_key
   terraform apply -var deploy_vms=true -var create_gateway=true -var enable_gateway_transit=true -var create_onprem_connection=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   az network nic show-effective-route-table -g $RG -n nic-vm-a -o table | grep 192.168
   az network nic show-effective-route-table -g $RG -n nic-vm-b -o table | grep 192.168
   ```

   Expected: Expected (designed, not tested): vm-a shows `192.168.100.0/24` with next hop `VirtualNetworkGateway` (source: virtual network gateway). vm-b shows no such row, because spoke-b does not use the remote gateway. Confirm on your own run.

**Checkpoint questions.**

- On which link is Allow gateway transit set, and on which is Use remote gateways? *Answer: Transit on the hub's link to the spoke; remote gateways on the spoke's link to the hub.*
- Why does vm-b have no on-premises route? *Answer: Its link does not use the remote gateway, and peering is not transitive for routes.*

**If it doesn't work.** A spoke link with Use remote gateways fails to create if the hub link does not allow transit, or the hub has no gateway. The lab orders the resources for this.

## Activity 6: Break/fix drills and an address-space change

**Goal.** Apply three broken setups, diagnose each from symptoms, and then change an address space and sync the peering.

**Exam skill.** Diagnose with effective routes, peering state and Network Watcher before touching anything, and know that peering must be synced after an address-space change.

1. **Break/fix 1: one-sided peering**: Apply the switch. Do not read the answer yet: use `diagnose.sh` and the ping.

   ```bash
   terraform apply -var deploy_vms=true -var break_fix=one_sided -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   ./scripts/diagnose.sh $RG vnet-hub
   az vm run-command invoke -g $RG -n vm-hub --command-id RunShellScript --scripts "ping -c 2 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   ```

   Expected: `hub-to-spoke-b` not Connected, and the ping fails. The fix is the missing link: `terraform apply -var break_fix=none`.

2. **Break/fix 2: forwarded traffic off on one spoke**: Needs the forwarding VM.

   ```bash
   terraform apply -var deploy_vms=true -var deploy_nva=true -var break_fix=no_forwarded -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   az vm run-command invoke -g $RG -n vm-a --command-id RunShellScript --scripts "ping -c 3 -W 2 10.20.1.4" --query "value[0].message" -o tsv
   az network watcher show-next-hop -g $RG --vm vm-a --source-ip 10.10.1.4 --dest-ip 10.20.1.4 -o table
   ```

   Expected: The ping fails, yet next hop shows `VirtualAppliance 10.0.2.4`: the route is right and the packet dies later. Read `spoke-b-to-hub` with `diagnose.sh`: `fwd False`. The fix: `break_fix=none`.

3. **Break/fix 3: spoke asks for a gateway the hub does not offer**: Needs the gateway (costly). The apply is expected to fail.

   ```bash
   terraform apply -var deploy_vms=true -var create_gateway=true -var enable_gateway_transit=true -var break_fix=no_transit -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   ```

   Expected: An error on `spoke-a-to-hub` saying the remote VNet has no gateway transit enabled (wording varies). The hub link has `allow_gateway_transit` false while the spoke asks for it.

4. **Bonus: overlapping address space**: Spoke-b is moved to 10.0.128.0/17, inside the hub's 10.0.0.0/16.

   ```bash
   terraform apply -var break_fix=overlap
   ```

   Expected: The peering between hub and spoke-b is rejected because the address spaces overlap (wording varies). Fix: renumber, as the guide's overlap section shows.

5. **Change an address space and sync the peering**: Restore `break_fix=none` first. Add a second range to spoke-a outside Terraform, then look at the sync level and sync.

   ```bash
   terraform apply -var deploy_vms=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
   az network vnet update -g $RG -n vnet-spoke-a --address-prefixes 10.10.0.0/16 10.12.0.0/16
   az network vnet peering list -g $RG --vnet-name vnet-hub --query "[].{name:name, sync:peeringSyncLevel}" -o table
   az network vnet peering sync -g $RG --vnet-name vnet-hub -n hub-to-spoke-a
   az network nic show-effective-route-table -g $RG -n nic-vm-hub -o table | grep 10.12
   ```

   Expected: Before the sync the hub's link reports a not-in-sync level (for example RemoteNotInSync) and has no `10.12.0.0/16` row. After the sync it is FullyInSync and the row appears. Exact values: check current Microsoft docs. Run `terraform apply` afterwards to remove the extra range.

**Checkpoint questions.**

- In break/fix 2 next hop looked correct. Where did the packet die? *Answer: At spoke-b's peering link: forwarded traffic is not allowed, so the NVA's forwarded packet is discarded on arrival.*
- Why was nothing wrong in Terraform state after the address-space change? *Answer: The change was made outside Terraform and Azure needs a peering sync; Terraform only reverts the range on the next apply.*

**If it doesn't work.** Always restore `break_fix=none` before the next drill, and read effective routes before you change anything.

## Clean-up

Destroy with every gate that you ever turned on, so Terraform removes everything it owns. The gateway takes 15 minutes or more to delete.

```bash
terraform destroy -var deploy_vms=true -var deploy_nva=true -var create_global_peering=true -var create_gateway=true -var enable_gateway_transit=true -var create_onprem_connection=true -var "admin_ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
az group exists -n $RG
```

Expected: `Destroy complete!` and `false`. Check the portal for any resource group named `NetworkWatcherRG` that Azure created for you; it is shared and not part of this lab.
