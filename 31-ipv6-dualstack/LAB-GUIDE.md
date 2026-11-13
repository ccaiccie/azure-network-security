# Lab guide: IPv6 and dual stack on Azure

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false` and `break_fix` defaults to `none`. A `-var` flag applies to that one command only: variables you leave out return to their defaults. IPv4 examples are RFC 1918 and RFC 5737 addresses; every IPv6 example uses the documentation prefix 2001:db8::/32 (RFC 3849), so Azure assigns your real addresses and yours will differ. Check current Microsoft docs and the provider docs for limits, defaults and attribute names.

## Activity 1: Plan the free baseline and read the dual-stack prefixes

**Goal.** Create the free network objects and read the IPv4 and IPv6 prefixes of the VNet and of each subnet.

**Exam skill:** Know that a dual-stack VNet lists two address spaces, that each subnet carries one IPv4 prefix and one IPv6 /64, and that the NSG has separate rules for each family.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false` and `break_fix` stays `none`. If you suspect Azure will refuse the documentation prefix, set `ipv6_vnet_prefix` to a ULA /48 such as `fd00:db8:31::/48` now.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 11 objects: 1 resource group, 1 VNet, 2 subnets, 1 NSG, 2 NSG associations, 1 route table, 1 route table association, 1 private DNS zone and 1 zone link. No VM and no public IP. (Designed, not tested; the exact count depends on the provider.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The output `resource_group` is `ds31-rg`.

3. **Read the VNet and its subnets**: The helper wraps `az network vnet show`.

   ```bash
   ./scripts/diagnose.sh vnet
   ```

   Expect: The address space lists 10.31.0.0/16 and your IPv6 /48. snet-web lists 10.31.1.0/24 and an IPv6 /64; snet-client lists 10.31.2.0/24 and a different /64.

4. **Read the NSG**: Look for one rule per family.

   ```bash
   ./scripts/diagnose.sh nsg
   ```

   Expect: allow-app-v4-in (priority 100, source 0.0.0.0/0) and allow-app-v6-in (priority 110, source ::/0). There is no rule that names both families.

5. **Checkpoint**: Why does each subnet list two prefixes? Answer: a subnet carries one prefix per family, and IPv6 subnets are /64. A subnet with only an IPv4 prefix cannot give a NIC an IPv6 address.

## Activity 2: Dual-stack NICs, DNS records and the private IPv6 path

**Goal.** Open gate 1, read the two IP configurations of a NIC, then reach the web VM over IPv4 and over IPv6 by name.

**Exam skill:** Explain why a NIC needs a second IP configuration for IPv6, how the A and AAAA records differ, and how to force one family with curl.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_vms = true` and paste the text of your public key into `admin_ssh_public_key`. The VMs bill by the hour until destroyed.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   terraform output web_v6
   ```

   Expect: About 6 objects are added: 2 NICs, 2 VMs, 1 A record and 1 AAAA record. The output `web_v6` is an address inside the web subnet's /64 (Azure chooses it).

2. **Read the NIC**: Two IP configurations, one per family.

   ```bash
   ./scripts/diagnose.sh nic vm-web-1
   ```

   Expect: ipconfig1: IPv4, 10.31.1.10, primary true. ipconfig2: IPv6, a dynamic address, primary false.

3. **Look inside the guest**: The guest must have the address and a default route.

   ```bash
   ./scripts/diagnose.sh v6 vm-web-1
   ```

   Expect: One global-scope inet6 address in the web /64, and a default route via the router's link-local address. If only fe80:: shows, the guest did not get DHCPv6: see 'if it does not work'.

4. **Resolve the name in both families**: The private zone has both records.

   ```bash
   ./scripts/diagnose.sh resolve vm-client-1 web.ds31.internal
   ```

   Expect: An IPv4 line with 10.31.1.10 and an IPv6 line with the web VM's IPv6 address.

5. **Request the page over each family**: The VNet-internal path is allowed by the default NSG rule AllowVnetInBound.

   ```bash
   ./scripts/diagnose.sh get vm-client-1 4 'http://web.ds31.internal:8080/'
   ./scripts/diagnose.sh get vm-client-1 6 'http://web.ds31.internal:8080/'
   ```

   Expect: Both print `HTTP 200`. The second one proves the private IPv6 path, the AAAA record and the guest's IPv6 stack.

6. **Read the effective routes**: Compare the two halves of the table.

   ```bash
   ./scripts/diagnose.sh routes vm-client-1
   ```

   Expect: IPv4 rows: the VNet route, the default route to Internet. IPv6 rows: the IPv6 VNet route (next hop Virtual network) and `::/0` to Internet. (Check your output: the exact rows depend on the API version.)

7. **Checkpoint**: What would curl -6 print if the AAAA record did not exist? Answer: a resolution failure and HTTP 000 (the name has no IPv6 address), even though the IPv6 path is fine.

## Activity 3: Dual-stack load balancer and public IPv6 on the client

**Goal.** Open gates 2 and 3, then reach the web VM through the IPv4 and the IPv6 frontend of the Standard load balancer.

**Exam skill:** Describe a dual-stack Standard load balancer: two frontends, two rules, two pools, a closed-by-default NSG, and a public IPv6 per VM for outbound.

1. **Open gates 2 and 3**: In `terraform.tfvars` set `deploy_lb = true` and `deploy_client_ips = true`. The load balancer and the public IPs bill while they exist.

   ```bash
   terraform plan -out=lb.tfplan
   terraform apply lb.tfplan
   terraform output lb_v4
   terraform output lb_v6
   ```

   Expect: About 14 objects are added: 4 public IPs (two for the load balancer, two for the client), the load balancer, 2 backend pools, 2 pool associations, 1 probe and 2 rules. (The NICs are updated in place.) The outputs are a public IPv4 and a public IPv6 address.

2. **Read the load balancer**: One frontend and one rule per family.

   ```bash
   ./scripts/diagnose.sh lb
   ```

   Expect: Frontends fe-v4 and fe-v6, pools be-v4 and be-v6, rules rule-v4-8080 and rule-v6-8080. The public IP table lists one IPv4 and one IPv6 address, both Standard.

3. **Request the page through each frontend**: Replace `<LB4>` and `<LB6>` with the outputs. An IPv6 address in a URL goes in square brackets. The client has its own public IPv4 and IPv6, so it can reach both from outside the VNet.

   ```bash
   ./scripts/diagnose.sh get vm-client-1 4 'http://<LB4>:8080/'
   ./scripts/diagnose.sh get vm-client-1 6 'http://[<LB6>]:8080/'
   ```

   Expect: Both print `HTTP 200`. The backend page says `hello from vm-web-1` whichever family you used.

4. **Compare the guest's public address with its private one**: Azure maps the public IPv6 to the NIC's private IPv6.

   ```bash
   ./scripts/diagnose.sh v6 vm-client-1
   ```

   Expect: The guest shows only its private IPv6 (in the client /64), not the public IPv6 address. There is no SNAT: the whole address belongs to the VM.

5. **Checkpoint**: Why must the NSG allow IPv6 for a load balancer that was already set up for IPv4? Answer: a Standard load balancer is closed by default, and an NSG rule matches one family only, so the IPv4 allow rule never admits an IPv6 packet.

## Activity 4: Break/fix: a missing IPv6 rule, a missing AAAA record and an IPv4-only UDR

**Goal.** Create each broken setup with the `break_fix` selector, observe the symptom, diagnose it, then restore.

**Exam skill:** Diagnose an IPv6 failure by layer: the name, the path and the rules, using curl -4 versus curl -6, the NSG list and the effective routes.

1. **Remove the IPv6 NSG rule**: The selector drops `allow-app-v6-in`. Read the plan first: one in-place change to the NSG.

   ```bash
   terraform apply -var 'break_fix=nsg_v4_only'
   ./scripts/diagnose.sh get vm-client-1 4 'http://<LB4>:8080/'
   ./scripts/diagnose.sh get vm-client-1 6 'http://[<LB6>]:8080/'
   ```

   Expect: IPv4: `HTTP 200`. IPv6: `HTTP 000` and `curl-failed` after the timeout. The name resolves, the load balancer forwards, and DenyAllInBound drops the packet. `./scripts/diagnose.sh nsg` shows no rule with source `::/0`.

2. **Restore and remove the AAAA record**: Switch the selector to the next case.

   ```bash
   terraform apply -var 'break_fix=no_aaaa'
   ./scripts/diagnose.sh dns
   ./scripts/diagnose.sh resolve vm-client-1 web.ds31.internal
   ./scripts/diagnose.sh get vm-client-1 6 'http://web.ds31.internal:8080/'
   ```

   Expect: The zone lists an A record and no AAAA record. The resolve output shows an IPv4 answer and `no-AAAA`. The curl over IPv6 prints `HTTP 000`: the failure is in the name, and the path is fine (curl -6 to the IPv6 address still works).

3. **Add an IPv4-only UDR**: The selector adds `0.0.0.0/0` to an address with no appliance, on snet-client.

   ```bash
   terraform apply -var 'break_fix=udr_v4_only'
   ./scripts/diagnose.sh routes vm-client-1
   ./scripts/diagnose.sh get vm-client-1 4 'http://<LB4>:8080/'
   ./scripts/diagnose.sh get vm-client-1 6 'http://[<LB6>]:8080/'
   ```

   Expect: The IPv4 rows show a user route for 0.0.0.0/0 to a virtual appliance; the IPv6 rows are unchanged. IPv4 prints `HTTP 000`, IPv6 prints `HTTP 200`. Imagine the appliance was a real firewall: IPv6 would bypass it.

4. **Restore**: Set the selector back.

   ```bash
   terraform apply -var 'break_fix=none'
   ./scripts/diagnose.sh get vm-client-1 6 'http://[<LB6>]:8080/'
   ```

   Expect: `HTTP 200` over both families again.

5. **Checkpoint**: In which of the three cases does the name still resolve, and why does that not help? Answer: in the NSG case the name resolves and the path is up, but a rule is missing; the layers fail independently.

## Activity 5: Peering with IPv6, then clean up

**Goal.** Open gate 4, see the peer's IPv4 and IPv6 prefixes in the effective routes, then destroy the lab.

**Exam skill:** Explain that peering carries both families, and tear down a gated lab safely.

1. **Open gate 4**: In `terraform.tfvars` set `deploy_peer = true`.

   ```bash
   terraform plan -out=peer.tfplan
   terraform apply peer.tfplan
   ./scripts/diagnose.sh peer
   ```

   Expect: About 4 objects are added: the peer VNet, its subnet and 2 peerings. Both peerings show `Connected`, and the remote address space lists an IPv4 and an IPv6 prefix.

2. **Read the effective routes**: The peer prefixes appear in both families.

   ```bash
   ./scripts/diagnose.sh routes vm-web-1
   ```

   Expect: A row for 10.32.0.0/16 and a row for the peer's IPv6 /48, both with next hop type VNet peering.

3. **Switch the gates off and destroy**: Set every gate back to `false` and `break_fix` to `none`, apply, then destroy, through your own approved workflow.

   ```bash
   terraform apply -var 'break_fix=none'
   terraform destroy
   az group exists -n ds31-rg
   ```

   Expect: Destroy complete. The last command prints `false`.

4. **Checkpoint**: What does the peering need on both sides, in both families? Answer: a non-overlapping IPv4 prefix and a non-overlapping IPv6 prefix on each VNet, and a peering object in each direction.

## If it does not work

* **No global IPv6 address in the guest.** Check `./scripts/diagnose.sh nic VM` for the IPv6 configuration and `./scripts/diagnose.sh vnet` for the subnet's /64. If both are right, the image did not run DHCPv6: check the netplan drop-in written by the boot file, or enable DHCPv6 for the interface your image uses.
* **Azure refuses the documentation prefix.** Set `ipv6_vnet_prefix` to a ULA /48 such as `fd00:db8:31::/48` and plan again.
* **The IPv6 curl fails with a URL error.** An IPv6 address in a URL needs square brackets, for example `http://[<LB6>]:8080/`.
* **Terraform reports an unsupported argument.** Provider attribute names change: check the provider docs for the IP configuration, load balancer rule and subnet arguments used here.
