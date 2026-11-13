# Lab guide: system routes, user routes and effective routes

**Designed, not tested.** The lab was written and reviewed but never applied to Azure, and no `az` command here was run. Outputs are expected behaviour from documentation. Check the current Microsoft documentation for limits, regions and prices. All commands run from the `terraform/` folder.

Variables: set `subscription_id` and `admin_ssh_public_key` in `terraform.tfvars`, then `deploy_lab = true`. After each `terraform apply`, load the resource group name once:

```bash
RG=$(terraform output -raw resource_group_name)
```

## Activity 1: Read the default system routes

**Goal.** Read the routes Azure gave the client with no user routes, and ask next hop for three destinations.

**Exam skill:** Name the default routes of a subnet and predict the next hop type for a same-VNet, a public and an unused private destination.

1. **Read the client's effective routes.** Open the effective routes of the client's NIC.

   ```bash
   az network nic show-effective-route-table -g "$RG" -n nic-a -o table
   ```

   Expected: Rows with source Default: 10.10.0.0/16 VnetLocal, 10.20.0.0/16 VNetPeering, 0.0.0.0/0 Internet, and None rows for the private ranges. Exact columns and extra rows may differ: check what your CLI prints.

2. **Ask next hop for three destinations.** Run the three checks, one per destination.

   ```bash
   for D in 10.10.2.10 10.20.1.20 198.51.100.10 10.30.4.4; do
     az network watcher show-next-hop -g "$RG" --vm vm-a --source-ip 10.10.1.10 --dest-ip "$D" -o table
   done
   ```

   Expected: Expect VnetLocal-type for 10.10.2.10, a peering type for 10.20.1.20 (the label may read VNetPeering), Internet for 198.51.100.10 and None for 10.30.4.4.

3. **Test the path.** Confirm the web service answers directly.

   ```bash
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/' --query "value[0].message" -o tsv
   ```

   Expected: A line such as `vm-b ok`.

If it does not work: run `terraform output active_routes` to confirm which gates are on, wait a few minutes after deploy for cloud-init, and re-read the effective routes (a stopped VM has none).

## Activity 2: Add a user route and watch it win the tie

**Goal.** Turn on the forward route, see the user route override the peering route, and find out why the connection now hangs.

**Exam skill:** Predict which route wins from prefix length and source, read the Invalid state, and explain why one steered direction is not enough for a stateful appliance.

1. **Turn on the forward gate.** Set `enable_udr_forward = true` in terraform.tfvars and apply.

   ```bash
   terraform plan -out=lab.tfplan
   terraform apply lab.tfplan
   ```

   Expected: One route and one association are added.

2. **Read the effective routes again.** Look for the user row and the Invalid peering row.

   ```bash
   az network nic show-effective-route-table -g "$RG" -n nic-a -o table
   ```

   Expected: 10.20.0.0/16 now appears twice: source User with next hop VirtualAppliance 10.10.2.10, and the Default peering row marked Invalid.

3. **Ask next hop.** Check the decision for the web server.

   ```bash
   az network watcher show-next-hop -g "$RG" --vm vm-a --source-ip 10.10.1.10 --dest-ip 10.20.1.20 -o table
   ```

   Expected: Next hop type VirtualAppliance, address 10.10.2.10, and the id of the route in rt-app.

4. **Send traffic and read the counters.** Zero the counters, send one request, read them.

   ```bash
   az vm run-command invoke -g "$RG" -n vm-nva --command-id RunShellScript --scripts 'iptables -Z FORWARD' --query "value[0].message" -o tsv
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/ ; echo exit=$?' --query "value[0].message" -o tsv
   az vm run-command invoke -g "$RG" -n vm-nva --command-id RunShellScript --scripts 'iptables -L FORWARD -v -n -x --line-numbers' --query "value[0].message" -o tsv
   ```

   Expected: Expected: curl times out (exit 28). Rule 2 counts the SYN. The reply skipped the appliance, so the next packets from the client are not a new SYN and rule 3 drops them. Only one direction is steered: Activity 3 fixes it.

If it does not work: run `terraform output active_routes` to confirm which gates are on, wait a few minutes after deploy for cloud-init, and re-read the effective routes (a stopped VM has none).

## Activity 3: Close the return path

**Goal.** Add the return route so both directions cross the appliance, and compare the counters.

**Exam skill:** Explain why a path with one steered direction fails against a stateful appliance, and why both directions must cross it.

1. **Turn on the return route.** Set `enable_return_route = true` and apply.

   ```bash
   terraform apply -auto-approve
   ```

   Expected: One route and one association are added on the work subnet.

2. **Read B's effective routes.** Look for 10.10.1.0/24 with source User.

   ```bash
   az network nic show-effective-route-table -g "$RG" -n nic-b -o table
   ```

   Expected: B shows 10.10.1.0/24 → VirtualAppliance 10.10.2.10 (User) next to the Default peering /16 for 10.10.0.0/16.

3. **Repeat the request.** Zero the counters, send one request, read them.

   ```bash
   az vm run-command invoke -g "$RG" -n vm-nva --command-id RunShellScript --scripts 'iptables -Z FORWARD' --query "value[0].message" -o tsv
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/' --query "value[0].message" -o tsv
   az vm run-command invoke -g "$RG" -n vm-nva --command-id RunShellScript --scripts 'iptables -L FORWARD -v -n -x --line-numbers' --query "value[0].message" -o tsv
   ```

   Expected: curl prints the page. Rule 1 (ESTABLISHED) and rule 2 (the SYN) both count packets: both directions crossed the appliance. Check B's log: `journalctl -u lab-web -n 5` shows the client 10.10.1.10.

If it does not work: run `terraform output active_routes` to confirm which gates are on, wait a few minutes after deploy for cloud-init, and re-read the effective routes (a stopped VM has none).

## Activity 4: Longer prefixes: blackhole, forced tunnel, service tag and propagation

**Goal.** Add routes that are longer or shorter than the existing ones, predict each effect, then read the BGP propagation flag.

**Exam skill:** Predict what a /24 to None, a 0.0.0.0/0 route and a tag route capture, and what propagation does and does not change.

1. **Add the blackhole.** Set `enable_blackhole_route = true` and apply, then ask next hop and test.

   ```bash
   terraform apply -auto-approve
   az network watcher show-next-hop -g "$RG" --vm vm-a --source-ip 10.10.1.10 --dest-ip 10.20.1.20 -o table
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/ ; echo exit=$?' --query "value[0].message" -o tsv
   ```

   Expected: Next hop None and curl times out (exit 28): the /24 beat the /16. Set the gate back to false and apply.

2. **Force the tunnel.** Set `enable_default_route = true` and apply, then check two next hops.

   ```bash
   terraform apply -auto-approve
   for D in 198.51.100.10 10.20.1.20; do
     az network watcher show-next-hop -g "$RG" --vm vm-a --source-ip 10.10.1.10 --dest-ip "$D" -o table
   done
   ```

   Expected: 198.51.100.10 goes to VirtualAppliance 10.10.2.10. 10.20.1.20 still follows its /16 route: a default route never captures longer prefixes.

3. **Add the service-tag route.** Set `enable_service_tag_route = true` and apply, then read the effective routes.

   ```bash
   terraform apply -auto-approve
   az network nic show-effective-route-table -g "$RG" -n nic-a -o table | head -40
   ```

   Expected: Many prefixes of the tag appear with source User and next hop Internet (the exact output differs by tag and region; check the current documentation).

4. **Turn propagation off and read the flag.** Set `bgp_route_propagation_enabled = false`, apply, then read the property.

   ```bash
   terraform apply -auto-approve
   az network route-table show -g "$RG" -n rt-app --query disableBgpRoutePropagation -o tsv
   ```

   Expected: `true`: gateway routes would be hidden on this subnet. The lab has no gateway, so no route disappears.

If it does not work: run `terraform output active_routes` to confirm which gates are on, wait a few minutes after deploy for cloud-init, and re-read the effective routes (a stopped VM has none).

## Activity 5: Break/fix drill: three faults

**Goal.** Use the fault variable to create each broken setup, diagnose it with only route tools and counters, then fix it.

**Exam skill:** Follow the diagnosis path: sender's routes, receiver's routes, appliance forwarding, then rules.

1. **Fault forwarding_off.** Set both route gates true and `fault = "forwarding_off"`, apply, then test.

   ```bash
   terraform apply -auto-approve
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/ ; echo exit=$?' --query "value[0].message" -o tsv
   az network nic show -g "$RG" -n nic-nva --query enableIPForwarding -o tsv
   ```

   Expected: curl times out; next hop and effective routes look correct; the NIC flag prints false. Set `fault = "none"` to fix.

2. **Fault missing_association.** Set `fault = "missing_association"` with both route gates true and apply.

   ```bash
   terraform apply -auto-approve
   az network nic show-effective-route-table -g "$RG" -n nic-a -o table
   az network route-table show -g "$RG" -n rt-app --query subnets -o tsv
   ```

   Expected: curl works, but the effective routes have no User row and the table lists no subnet. The appliance counters stay at zero. Set `fault = "none"`.

3. **Fault return_only.** Set `fault = "return_only"` and apply, then test and read the drop counter.

   ```bash
   terraform apply -auto-approve
   az vm run-command invoke -g "$RG" -n vm-a --command-id RunShellScript --scripts 'curl -sS -m 5 http://10.20.1.20:8080/ ; echo exit=$?' --query "value[0].message" -o tsv
   az vm run-command invoke -g "$RG" -n vm-nva --command-id RunShellScript --scripts 'iptables -L FORWARD -v -n -x --line-numbers' --query "value[0].message" -o tsv
   ```

   Expected: curl times out; B logged the SYN (`journalctl -u lab-web`); the appliance's drop rule counts packets. Set `fault = "none"`.

If it does not work: run `terraform output active_routes` to confirm which gates are on, wait a few minutes after deploy for cloud-init, and re-read the effective routes (a stopped VM has none).

## Clean-up

```bash
terraform destroy
```
