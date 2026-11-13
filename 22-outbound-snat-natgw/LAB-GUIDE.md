# Lab guide: outbound connectivity and SNAT

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses in the expected output are RFC 5737 documentation examples; yours will differ. Check current Microsoft docs for limits, retirement dates, metric names and provider attribute names.

## Activity 1: Plan the free baseline and read the private subnet flag

**Goal.** Create the free network objects and read the property that decides whether a subnet still offers default outbound access.

**Exam skill:** Know that default outbound access is a subnet property (defaultOutboundAccess), that it is being retired for new VNets, and that Terraform names it default_outbound_access_enabled.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 5 objects: 1 resource group, 1 VNet and 3 subnets. No VM, no public IP, no NAT gateway. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the outputs `resource_group` and `vnet_name`; every public address output is empty.

3. **Read the flag on each subnet**: The property is shown as `defaultOutboundAccess` in the Azure CLI.

   ```bash
   az network vnet subnet show -g snat22-rg --vnet-name snat22-vnet -n snet-nat --query defaultOutboundAccess
   ```

   Expect: `true` in this lab (the variable default). A newly created production VNet may show `false`; check current docs for the platform default.

4. **Checkpoint**: Which property switches a subnet from implicit to explicit-only outbound, and what Terraform argument sets it? Answer: `defaultOutboundAccess = false`, written `default_outbound_access_enabled = false` in the azurerm subnet resource.

## Activity 2: Deploy the VMs and meet default outbound access

**Goal.** Add the three VMs (gate 1) with no explicit outbound method, and see that they still reach the Internet through an address you do not own.

**Exam skill:** Recognise default outbound access: no public IP resource in your subscription, a Microsoft-owned egress IP, and what changes when the private subnet flag is set.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_vms = true` and paste the text of your public key into `admin_ssh_public_key`.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: Three NICs and three Linux VMs. Billing starts.

2. **Confirm that you own no public IP**

   ```bash
   az network public-ip list -g snat22-rg -o table
   ```

   Expect: An empty list. The VMs have no public IP resource.

3. **Ask each VM what address it appears to have**: The helper runs `curl` against a plain-text IP echo service on each VM through the Azure agent.

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: Three addresses. All three come from Microsoft's pool (default outbound access). They are not in your subscription, and they may change. Record them.

4. **Read the effective routes**

   ```bash
   ./scripts/egress-check.sh routes
   ```

   Expect: Each NIC has 10.50.0.0/16 with next hop VnetLocal and 0.0.0.0/0 with next hop Internet, source Default. The route does not say which Internet method applies.

5. **Make the subnets private**: Set `default_outbound_access_enabled = false`, plan, and apply. Whether running VMs need a restart for the change to bite depends on the current platform behaviour; check current docs, and restart the VMs if the test still works.

   ```bash
   terraform apply
   ./scripts/egress-check.sh ip
   ```

   Expect: `TIMEOUT` for all three VMs: with no explicit method there is no outbound path. Set the flag back to `true` before the next activity.

6. **Checkpoint**: The VM had no public IP and still reached the Internet. Why is that a risk? Answer: the address belongs to Microsoft, is not stable, cannot be sized or watched, and the path is being retired for new VNets.

## Activity 3: Add a NAT gateway: egress IP, idle timeout and prefix

**Goal.** Attach a NAT gateway to snet-nat (gate 2) and see that vm-nat now leaves from an address you own.

**Exam skill:** Know that a NAT gateway is subnet-wide, outbound-only, uses 64,512 ports per IP on demand, and has a 4 minute idle timeout that can be raised to 120.

1. **Open gate 2**: Set `deploy_nat_gateway = true`.

   ```bash
   terraform plan -out=nat.tfplan
   terraform apply nat.tfplan
   ```

   Expect: A Standard public IP, a NAT gateway, the IP association and the subnet association. Output `nat_gateway_ip` shows the address.

2. **Read the attachment**

   ```bash
   ./scripts/egress-check.sh attach
   ```

   Expect: snet-nat shows a `natGateway` id. snet-lb and snet-fw show `null`.

3. **Ask the VMs again**

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-nat reports the NAT gateway's address, the same as `terraform output nat_gateway_ip`. vm-lb and vm-fw still use default outbound.

4. **Read the NAT gateway settings**

   ```bash
   az network nat gateway show -g snat22-rg -n snat22-natgw --query "{sku:sku.name, idleMinutes:idleTimeoutInMinutes}" -o json
   ```

   Expect: SKU Standard and 4 idle minutes.

5. **Raise the idle timeout and swap in a prefix**: Set `nat_idle_timeout_minutes = 10` and `nat_public_ip_prefix_length = 31`, then plan and apply. The single public IP is replaced by a prefix with 2 addresses.

   ```bash
   terraform plan -out=nat2.tfplan
   terraform apply nat2.tfplan
   terraform output nat_gateway_prefix
   ```

   Expect: A /31 prefix. The egress address of vm-nat is now one of the two addresses in the prefix. Run the IP check a few times to see them. Plan for the address change when a partner has allow-listed the old one.

6. **Checkpoint**: How many SNAT ports does one NAT gateway public IP provide, and how many IPs can a gateway use? Answer: 64,512 ports per IP and up to 16 IPs (a /28 prefix holds 16).

## Activity 4: Precedence: an instance public IP and a UDR against the NAT gateway

**Goal.** Add a public IP to vm-nat (gate 5) and a UDR to a firewall (gate 4), and find out which one decides the egress IP.

**Exam skill:** State the precedence: UDR to a firewall or NVA first, then NAT gateway, then an instance public IP, then a load balancer, then default outbound.

1. **Put a public IP on vm-nat**: Set `attach_vm_public_ip = true`. The NAT gateway stays attached to the subnet.

   ```bash
   terraform plan -out=pip.tfplan
   terraform apply pip.tfplan
   terraform output vm_nat_public_ip
   ```

   Expect: A second public address, now on vm-nat's NIC.

2. **Ask vm-nat which address it uses**

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-nat still reports the **NAT gateway's** address, not its own public IP. The NAT gateway takes precedence for new outbound connections. (Replies to inbound connections still use the instance IP.)

3. **Add the firewall and its UDR**: Set `deploy_firewall = true`. This is the most expensive gate: do Activity 6 straight afterwards, then destroy it. Also set `nat_on_fw_subnet = true` so snet-fw has both a NAT gateway and a UDR.

   ```bash
   terraform plan -out=fw.tfplan
   terraform apply fw.tfplan
   terraform output firewall_public_ip
   ```

   Expect: A firewall, its public IP, a policy, a route table and its association with snet-fw. Provisioning the firewall can take several minutes.

4. **Read the effective routes of vm-fw**

   ```bash
   ./scripts/egress-check.sh routes
   ```

   Expect: For vm-fw, 0.0.0.0/0 now has next hop VirtualAppliance (the firewall's private IP) with source User; the default Internet route is shown as not active.

5. **Ask vm-fw which address it uses**

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-fw reports the **firewall's** public IP, not the NAT gateway's, although the NAT gateway is attached to its subnet. The route came first.

6. **Checkpoint**: Put the four methods in order for a VM with a UDR, a NAT gateway, an instance public IP and a load balancer. Answer: UDR to the firewall, NAT gateway, instance public IP, load balancer.

## Activity 5: Load balancer outbound rule, manual ports and SNAT exhaustion

**Goal.** Give vm-lb an outbound rule (gate 3), shrink its port share to 8 and watch a burst of connections exhaust it.

**Exam skill:** Read the SNAT metrics that prove exhaustion and explain why a static per-VM share of ports behaves differently from a NAT gateway.

1. **Open gate 3**: Set `deploy_lb_outbound = true` and keep `lb_allocated_ports = 1024`.

   ```bash
   terraform plan -out=lb.tfplan
   terraform apply lb.tfplan
   terraform output lb_frontend_ip
   ```

   Expect: A public IP, a load balancer with one frontend, a backend pool containing vm-lb's NIC, and an outbound rule. Nothing can arrive through this load balancer: it has no load balancing rules.

2. **Ask vm-lb which address it uses**

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-lb reports the load balancer's frontend IP.

3. **Run a burst with the generous allocation**: The burst script runs on the VM. Keep the destination and the count small. It opens 30 connections at once to one destination and holds them for 15 seconds.

   ```bash
   az vm run-command invoke -g snat22-rg -n vm-lb --command-id RunShellScript --scripts @scripts/snat-burst.sh --parameters 30 example.com 80 15 --query "value[0].message" -o tsv
   ```

   Expect: `attempted=30 connected=30 never_connected=0`. A share of 1024 ports is plenty.

4. **Shrink the share to 8 ports and repeat**: Set `lb_allocated_ports = 8`, plan and apply, then run the same burst.

   ```bash
   terraform apply
   az vm run-command invoke -g snat22-rg -n vm-lb --command-id RunShellScript --scripts @scripts/snat-burst.sh --parameters 30 example.com 80 15 --query "value[0].message" -o tsv
   ```

   Expect: About 8 connections hold and the rest never connect, for example `connected=8 never_connected=22`. The exact count varies. Connections to one destination need one port each.

5. **Read the metrics**: Wait a few minutes for the metrics to appear. The helper lists the load balancer's SNAT metrics for the last 30 minutes.

   ```bash
   ./scripts/egress-check.sh metrics
   ```

   Expect: `SnatConnectionCount` has Failed connections, and `UsedSnatPorts` reaches `AllocatedSnatPorts`. In the portal, split SNAT Connection Count by Connection State.

6. **Restore the share and checkpoint**: Set `lb_allocated_ports = 1024` again. Why would the same burst succeed behind the NAT gateway? Answer: the NAT gateway hands ports out on demand from 64,512 per IP, so one VM can use them all; the load balancer gives each VM a fixed share.

## Activity 6: Azure Firewall egress: the SNAT IP and the rule that allows it

**Goal.** See Azure Firewall SNAT in practice, find its log entry, and confirm that the partner would see the firewall's address.

**Exam skill:** Know that a firewall SNATs to one of its public IPs, that you must allow-list all of them, and where the SNAT port utilization metric is.

1. **Confirm the path again**: Gate 4 is already open from Activity 4. If it is not, open it now.

   ```bash
   ./scripts/egress-check.sh ip
   terraform output firewall_public_ip
   ```

   Expect: vm-fw reports the same address as `firewall_public_ip`.

2. **Prove the firewall carried the connection**: Enable diagnostic settings to a Log Analytics workspace first (not created by this lab), then run the query in `queries/snat-queries.kql`.

   ```bash
   az monitor diagnostic-settings list --resource <FIREWALL_ID> -o table
   ```

   Expect: Optional. A row with Action Allow and Rule `snet-fw-web`. Table names depend on the log mode; check current docs.

3. **Look at the SNAT port metric**: In the portal open the firewall, Metrics, and choose SNAT port utilization.

   ```bash
   az monitor metrics list --resource <FIREWALL_ID> --metric SNATPortUtilization --interval PT1M --offset 30m -o table
   ```

   Expect: A low percentage. It would rise toward 100 when connections to one destination pile up.

4. **Think about several public IPs**: A firewall can have more than one public IP. Which one will a connection use?

   Expect: Answer: the firewall chooses; do not rely on a particular one. A partner must allow-list every firewall public IP, and a public IP prefix makes that one CIDR.

5. **Remove the expensive gate**: Set `deploy_firewall = false` and `nat_on_fw_subnet = false`, plan and apply. The route table association goes with the firewall, so vm-fw returns to default outbound.

   ```bash
   terraform apply
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-fw reports a Microsoft-owned address again (or the NAT gateway's address if you left `nat_on_fw_subnet = true`).

6. **Checkpoint**: Why must a partner allow-list every firewall public IP? Answer: SNAT picks one of them per connection, and you cannot pin it.

## Activity 7: Private subnets, metrics review and clean-up

**Goal.** Make every VM subnet private so nothing leaves by accident, confirm that explicit methods keep working, and destroy the lab.

**Exam skill:** Combine the private subnet flag with an explicit method per subnet, and know the three SNAT metrics by name.

1. **Set the flag**: Set `default_outbound_access_enabled = false`. Keep the NAT gateway and the load balancer. Plan and apply, and restart the VMs if the platform needs it.

   ```bash
   terraform apply
   ./scripts/egress-check.sh attach
   ```

   Expect: All three subnets show `defaultOutboundAccess: false`.

2. **Test again**

   ```bash
   ./scripts/egress-check.sh ip
   ```

   Expect: vm-nat reports the NAT gateway's address and vm-lb reports the load balancer's address. vm-fw prints `TIMEOUT`: it has no explicit method any more (the firewall is gone).

3. **Name the three metrics**: From memory, then check the portal.

   Expect: NAT gateway and load balancer: SNAT Connection Count (split by Connection State). Load balancer: Allocated SNAT Ports and Used SNAT Ports. Firewall: SNAT port utilization.

4. **Destroy everything**: Through your approved workflow. Gates open means the resources are real, so destroy in one plan.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: All lab objects are deleted. Check that `az network public-ip list -g snat22-rg` fails because the group is gone.

5. **Checkpoint**: Which single flag removes accidental Internet access from a subnet, and what must you add so the VMs still work? Answer: the private subnet flag; an explicit method such as a NAT gateway or a UDR to a firewall.
