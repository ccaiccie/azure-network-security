# Lab guide: Azure Bastion and Just-in-Time VM access

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script. Bastion and the Defender plan are costly and are behind gates that default to `false`. The Just-in-Time policy is created in the portal.

## Activity 1: Plan the free baseline and read the Bastion subnet and its NSG

**Goal.** Create the hub, the spoke, the AzureBastionSubnet and the Bastion NSG for free, then read the subnet name, size and the NSG rules a Bastion host would need.

**Exam skill:** Know that the subnet must be named AzureBastionSubnet and be /26 or larger, and name the NSG rules Bastion needs, including GatewayManager.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds a resource group, two VNets, two subnets (the hub AzureBastionSubnet and the spoke snet-app), the Bastion NSG with its rules and its association. No VM, no public IP, no Bastion. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. Nothing in the baseline bills by the hour.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The outputs `bastion_id` and `vm_private_ip` are empty.

3. **Read the subnet**

   ```bash
   az network vnet subnet show -g bas33-rg --vnet-name bas33-vnet-hub -n AzureBastionSubnet --query "{name:name, prefix:addressPrefix, nsg:networkSecurityGroup.id}" -o json
   ```

   Expect: The name is `AzureBastionSubnet`, the prefix is `10.33.250.0/26`, and an NSG is attached.

4. **Read the NSG rules**

   ```bash
   az network nsg rule list -g bas33-rg --nsg-name bas33-nsg-bastion --query "[].{n:name, dir:direction, pri:priority, port:destinationPortRange, ports:destinationPortRanges, src:sourceAddressPrefix}" -o table
   ```

   Expect: Four inbound rules (Internet 443, GatewayManager 443, AzureLoadBalancer 443, data plane 8080 and 5701) and four outbound rules. (Check the current Bastion NSG page: the set may have changed.)

5. **Checkpoint**: Which single rule would you check first if Bastion deployed but every connection failed? Answer: the inbound 443 rule from the service tag GatewayManager. Without it the control plane cannot manage the hosts.

## Activity 2: Add the private VM and prove access works without any network path

**Goal.** Open gate 1 to create vm-app in the spoke with no public IP, peer the two VNets, and reach the VM with run command, which needs no inbound network path.

**Exam skill:** Know that a VM with no public IP is still manageable, that peering links the hub and the spoke, and that run command and the serial console are break-glass paths.

1. **Open gate 1**: Set `deploy_workload = true` and paste your public key text into `admin_ssh_public_key`. The VM has no public IP and no inbound rule from the Internet.

   ```bash
   terraform plan -out=workload.tfplan
   terraform apply workload.tfplan
   ```

   Expect: A NIC, a small Linux VM with boot diagnostics, an app NSG, and two peerings. Small hourly cost for the VM.

2. **Read the NIC**

   ```bash
   az network nic show -g bas33-rg -n bas33-nic-app --query "{private:ipConfigurations[0].privateIPAddress, public:ipConfigurations[0].publicIPAddress.id}" -o json
   ```

   Expect: `private` is `10.34.1.4` and `public` is null: the VM cannot be reached from the Internet.

3. **Read the peering**

   ```bash
   az network vnet peering list -g bas33-rg --vnet-name bas33-vnet-hub --query "[].{name:name, state:peeringState, access:allowVirtualNetworkAccess}" -o table
   ```

   Expect: One peering with state `Connected` and access true.

4. **Run a command without any network path**: Run command goes through the VM agent and the Azure control plane, not through the NSG.

   ```bash
   az vm run-command invoke -g bas33-rg -n bas33-vm-app --command-id RunShellScript --scripts "hostname; ss -tln | grep ':22'"
   ```

   Expect: The hostname and a line showing that SSH listens on port 22. This proves the VM is healthy even though nothing can reach it.

5. **Checkpoint**: How can you manage a VM that has no public IP and no open port? Answer: through Bastion (a managed door), through run command or the serial console (the control plane), or through a private path such as a VPN.

## Activity 3: Deploy Bastion (costly) and connect from the portal

**Goal.** Open gate 2 to create a Bastion host in the hub and open an SSH session to vm-app through the portal. Turn on the audit log.

**Exam skill:** Know the Bastion deployment pieces (subnet, Standard static public IP, NSG), that Bastion bills per hour, and the Reader roles a user needs.

1. **Read the cost warning first**: Bastion bills per hour from creation until it is deleted. The lab needs two switches so that one typo cannot create it, and the default SKU is Basic. Plan to destroy it in the same sitting (check current pricing).

   ```bash
   grep -n "accept_bastion_cost" variables.tf
   ```

   Expect: The variable defaults to `false` and its description starts with a cost warning.

2. **Open gate 2 with the acknowledgement**: Set both `deploy_bastion = true` and `accept_bastion_cost = true`. Leave `bastion_sku = "Basic"`.

   ```bash
   terraform plan -out=bastion.tfplan
   terraform apply bastion.tfplan
   ```

   Expect: A Standard static public IP, a Bastion host (this can take several minutes), a workspace and a diagnostic setting for `BastionAuditLogs`.

3. **Read the Bastion**

   ```bash
   az network bastion show -g bas33-rg -n bas33-bastion --query "{sku:sku.name, state:provisioningState, subnet:ipConfigurations[0].subnet.id}" -o json
   ```

   Expect: `sku` is Basic, `state` is Succeeded, and the subnet is the AzureBastionSubnet.

4. **Connect from the portal**: Portal only: open `bas33-vm-app`, then Connect, Bastion. Enter `azureuser` and your private key. (Designed, not tested.)

   Expect: A browser tab opens a shell on vm-app. If Connect, Bastion is missing, check the Reader roles on the VM, its NIC, the Bastion and the VNet.

5. **Checkpoint**: The VM has no public IP. Which two addresses took part in the session? Answer: your public IP to Bastion's public IP on 443, and Bastion's private address in the subnet to 10.34.1.4 on port 22.

## Activity 4: Standard features: native client, tunnel, IP-based connection (costly)

**Goal.** Raise the SKU to Standard, turn on the native client and IP-based connection, and use your own ssh through a tunnel and by private IP.

**Exam skill:** Know which features need Standard or higher (native client, tunnelling, IP-based connection, shareable links) and how az network bastion ssh and tunnel are used.

1. **Change the SKU and the features**: Set `bastion_sku = "Standard"`, `bastion_native_client = true` and `bastion_ip_connect = true`, then apply. Standard costs more per hour than Basic (check current pricing). Upgrading in place is possible; a downgrade recreates the host.

   ```bash
   terraform plan -out=std.tfplan
   terraform apply std.tfplan
   ```

   Expect: The Bastion shows `sku` Standard, tunnelling and IP connect enabled.

2. **Connect with the native client**

   ```bash
   az login
   az network bastion ssh -g bas33-rg -n bas33-bastion --target-resource-id $(az vm show -g bas33-rg -n bas33-vm-app --query id -o tsv) --auth-type ssh-key --username azureuser --ssh-key ~/.ssh/id_ed25519
   ```

   Expect: Your own ssh opens a shell on vm-app. The azure-cli `ssh` extension may be required; check current docs for the flags.

3. **Open a tunnel**: The tunnel runs in the foreground. Open a second terminal for the ssh command.

   ```bash
   az network bastion tunnel -g bas33-rg -n bas33-bastion --target-resource-id $(az vm show -g bas33-rg -n bas33-vm-app --query id -o tsv) --resource-port 22 --port 50022
   ssh -p 50022 azureuser@127.0.0.1
   ```

   Expect: A local port 50022 forwards to port 22 on vm-app, and ssh through it works.

4. **Connect by private IP**: IP-based connection takes an address instead of a VM resource.

   ```bash
   az network bastion ssh -g bas33-rg -n bas33-bastion --target-ip-address 10.34.1.4 --auth-type ssh-key --username azureuser --ssh-key ~/.ssh/id_ed25519
   ```

   Expect: The same shell as step 2. With `bastion_ip_connect = false` this command fails: that is break/fix case 4.

5. **Checkpoint**: Why would you use the IP-based connection for a server in your office? Answer: it is not an Azure VM resource, so there is nothing to pick in the portal; the address is routable from the Bastion VNet over VPN or ExpressRoute.

## Activity 5: Defender for Servers plan and Just-in-Time access (costly, partly portal-only)

**Goal.** Turn on the Defender for Servers plan, enable JIT on vm-app in the portal, request access and watch the NSG rule appear and disappear.

**Exam skill:** Know that JIT needs Defender for Servers Plan 2, that it injects a temporary allow rule at a lower priority number than its deny rule, and that requests are bound to a source and a time.

1. **Read the cost warning first**: The Defender for Servers plan is a subscription-wide, per-server monthly charge (check current pricing). Turn it on only in a subscription where that is acceptable and plan to turn it off again.

   ```bash
   grep -n "accept_defender_cost" variables.tf
   ```

   Expect: The variable defaults to `false` and its description starts with a cost warning.

2. **Open gate 3 and give vm-app a temporary public IP**: Set `deploy_defender_servers = true`, `accept_defender_cost = true` and `vm_public_ip = true` (JIT here protects a direct path; with Bastion alone you would not need it).

   ```bash
   terraform plan -out=jit.tfplan
   terraform apply jit.tfplan
   ```

   Expect: The plan resource `VirtualMachines` is on tier Standard, subplan P2, and a Standard public IP is attached to the NIC.

3. **Enable JIT in the portal**: Portal only: Defender for Cloud, Workload protections, Just-in-time VM access, select vm-app, Enable JIT. Choose port 22, protocol TCP, allowed source: per request, maximum request time 2 hours. The Terraform provider has no simple resource for this step. (Designed, not tested.)

   Expect: vm-app is listed as Configured. Check the NSG: deny rules for the chosen port were added.

4. **Read the NSG before the request**

   ```bash
   az network nsg rule list -g bas33-rg --nsg-name bas33-nsg-app --query "[].{n:name, pri:priority, access:access, port:destinationPortRange, src:sourceAddressPrefix}" -o table
   ```

   Expect: A JIT deny rule for 22 sits at a low priority number, above the defaults. (Exact name and number are chosen by the service.)

5. **Request access, then read the NSG again**: Portal: Request access, port 22, My IP, 1 hour. (Designed, not tested.) Then run the read command again.

   ```bash
   az network nsg rule list -g bas33-rg --nsg-name bas33-nsg-app --query "[].{n:name, pri:priority, access:access, port:destinationPortRange, src:sourceAddressPrefix}" -o table
   ```

   Expect: An allow rule for 22 from your IP with a lower priority number than the deny rule. When the hour ends, it is removed.

6. **Checkpoint**: Why is the allow rule evaluated before the deny rule? Answer: NSGs are evaluated from the lowest priority number up, and JIT gives its allow rule a lower number than its deny rule.

## Activity 6: Audit logs: Bastion sessions and JIT requests

**Goal.** Query BastionAuditLogs for your sessions and the activity log for the JIT request.

**Exam skill:** Know where Bastion sessions and JIT requests are recorded, and that a diagnostic setting is needed for Bastion logs.

1. **List the diagnostic setting**

   ```bash
   az monitor diagnostic-settings list --resource $(az network bastion show -g bas33-rg -n bas33-bastion --query id -o tsv) --query "value[].{name:name, logs:logs[].category}" -o json
   ```

   Expect: The category `BastionAuditLogs` is sent to the workspace. (Check the category name in your own resource.)

2. **Query the sessions**: Ingestion can take a few minutes. Use the Logs blade of the workspace and the saved queries in `queries/bastion-queries.kql`.

   ```bash
   MicrosoftAzureBastionAuditLogs
   | order by TimeGenerated desc
   | project TimeGenerated, UserName, ClientIpAddress, TargetVMIPAddress, Protocol
   ```

   Expect: One row for each session you opened in Activities 3 and 4. The table and column names depend on the log mode: check current docs.

3. **Find the JIT request**

   ```bash
   az monitor activity-log list --resource-group bas33-rg --offset 1d --query "[?contains(operationName.value, 'jitNetworkAccessPolicies')].{when:eventTimestamp, who:caller, op:operationName.localizedValue}" -o table
   ```

   Expect: A row for the initiate operation with your user name. (JIT policy operations may be logged at the subscription: widen the filter if the list is empty.)

4. **Checkpoint**: Which log shows who opened a Bastion session, and which shows who asked for a JIT port? Answer: BastionAuditLogs through a diagnostic setting; and the activity log.

## Activity 7: Break/fix drills from variables

**Goal.** Cause the four break/fix cases on purpose with free switches, find each with a read-only command, then undo it.

**Exam skill:** Diagnose Bastion and JIT faults from the NSG rules, the effective security rules, the peering state and the SKU features.

1. **Case 1: remove the GatewayManager rule**: Set `bastion_nsg_include_gatewaymanager = false` and apply. Then try the portal connection or read the NSG.

   ```bash
   terraform apply
   ./scripts/bastion-check.sh nsg
   ```

   Expect: The NSG list lacks the GatewayManager rule and the portal shows a connection or health error. Set it back to `true` and apply.

2. **Case 2: add a second NSG on the NIC**: Set `nic_nsg_blocks_ssh = true` and apply. Request JIT access again if you completed Activity 5.

   ```bash
   terraform apply
   az network nic list-effective-nsg -g bas33-rg -n bas33-nic-app -o json
   ```

   Expect: The effective rules list two NSGs: the subnet NSG with a JIT allow rule and the NIC NSG with a deny for 22 from the Internet. Set it back to `false`.

3. **Case 3: remove the peering**: Set `peer_spoke_to_hub = false` and apply.

   ```bash
   terraform apply
   ./scripts/bastion-check.sh peering
   ```

   Expect: The peering list is empty, and Bastion no longer lists or reaches vm-app. Set it back to `true`.

4. **Case 4: switch IP-based connection off**: With `bastion_sku = "Standard"`, set `bastion_ip_connect = false` and apply. Repeat the `--target-ip-address` command from Activity 4.

   ```bash
   terraform apply
   ./scripts/bastion-check.sh bastion
   ```

   Expect: The command fails and the Bastion shows `ipConnect` false. Set it back to `true`.

5. **Checkpoint**: Which tool shows the merged rules from both NSGs that apply to one NIC? Answer: effective security rules (Network Watcher, or `az network nic list-effective-nsg`).

## Activity 8: Static check, paper review and clean-up

**Goal.** Run the static check of the lab files, review the access-path table on paper, then destroy the costly stages first.

**Exam skill:** Know the order of clean-up (the host and the plan first), that Bastion and the Defender plan keep billing until removed, and how to turn off JIT.

1. **Run the static check**: It reads local files only and is whitespace-tolerant.

   ```bash
   ./scripts/check-lab.sh
   ```

   Expect: Lines starting with `ok` and a final `ALL CHECKS PASSED`.

2. **Paper review**: For three real VMs of your own, write which access path you would use (Bastion, JIT, VPN, run command, Arc) and why. Check each against the table in the guide.

   Expect: A one-page table of VM, path, port and who may use it.

3. **Close the costly gates first**: Set `deploy_bastion`, `accept_bastion_cost`, `deploy_defender_servers` and `accept_defender_cost` to `false`, set `vm_public_ip = false` and apply. Remove the JIT policy in the portal first (Defender for Cloud, Just-in-time VM access, Remove).

   ```bash
   terraform apply
   ```

   Expect: The Bastion, its public IP and the plan go before anything else.

4. **Destroy everything**: Then destroy the whole state with your own approved workflow.

   ```bash
   terraform destroy
   ```

5. **Check nothing is left**

   ```bash
   az network bastion list -g bas33-rg -o table
   az security pricing show -n VirtualMachines --query pricingTier -o tsv
   ```

   Expect: An empty list (or no resource group) and a tier of `Free` for VirtualMachines.
