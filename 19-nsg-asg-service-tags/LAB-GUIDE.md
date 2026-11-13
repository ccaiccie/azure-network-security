# Lab guide: NSG, application security groups and service tags

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All five gates default to `false`. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, SKU facts and attribute names.

## Activity 1: Plan the closed baseline and read the default rules

**Goal.** Create the free objects and read every rule an NSG has before you write one.

**Exam skill:** Know the six default rules, their priorities (65000, 65001, 65500) and that custom rules below 65000 override them.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 11 objects: 1 resource group, 1 VNet, 3 subnets, 2 ASGs, 2 NSGs and 2 subnet associations. No VM, no endpoint, no storage account. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the outputs `resource_group`, `vnet_name` and empty NIC names.

3. **List the rules of nsg-app, defaults included**: The `--include-default` flag adds the six built-in rules to the list.

   ```bash
   az network nsg rule list -g nsg19-rg --nsg-name nsg-app --include-default -o table
   ```

   Expect: Four custom rules (100 and 200 inbound, 100 and 4000 outbound) and six default rules: AllowVnetInBound 65000, AllowAzureLoadBalancerInBound 65001, DenyAllInBound 65500, AllowVnetOutBound 65000, AllowInternetOutBound 65001, DenyAllOutBound 65500.

4. **Checkpoint**: Which default rule makes an NSG with no custom rules still allow VM to VM traffic in the same VNet? Answer: AllowVnetInBound (65000), because the VirtualNetwork tag covers both addresses.

## Activity 2: Deploy the VMs and read the effective security rules

**Goal.** Add the two VMs (gate 1) and read what Azure really applies to a NIC.

**Exam skill:** Read effective security rules and see ASG names expanded into the addresses of their member NICs.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_vms = true` and paste your public key text into `admin_ssh_public_key`. The VMs bill by the hour until destroyed.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: About 7 objects are added: 2 NICs, 2 Linux VMs and 2 ASG memberships. The outputs now show `web-1-nic` and `app-1-nic`.

2. **Read the effective rules of the app NIC**: Effective security rules merge every NSG that applies to the NIC.

   ```bash
   az network nic list-effective-nsg -g nsg19-rg -n app-1-nic -o json
   ```

   Expect: One NSG, nsg-app (from the subnet), with your four rules and the defaults. The ASG fields are shown as expanded address lists: asg-web as 10.30.1.10 and asg-app as 10.30.2.10. The exact JSON field names can change; check the current CLI output.

3. **Confirm the listener is up**: The cloud-init script started a listener on app-1. `run-command` goes through the Azure agent, not through the NSGs.

   ```bash
   az vm run-command invoke -g nsg19-rg -n app-1 --command-id RunShellScript --scripts "ss -ltn | grep 8080"
   ```

   Expect: A LISTEN line on 0.0.0.0:8080. If the VM was just created, wait a minute for cloud-init and retry.

4. **Checkpoint**: Why does the effective rule list show addresses where you wrote ASG names? Answer: the ASG is only a label for NICs. Azure expands it to the private addresses of the member NICs when it builds the rules.

## Activity 3: Prove allow and deny with IP flow verify

**Goal.** Test four tuples and name the rule that decided each one.

**Exam skill:** Use IP flow verify to turn 'it times out' into 'rule X in NSG Y denied it'.

1. **Run the four checks**: The script wraps `az network watcher test-ip-flow`. Inbound checks describe the packet from the receiving VM's point of view: local is the VM, remote is the sender.

   ```bash
   ./scripts/verify.sh flows
   ```

   Expect: Check 1 web to app 8080: Allow, rule allow-web-to-app-8080. Check 2 web to app 22: Deny, rule deny-vnet-to-app. Check 3 app to Internet 443: Deny, rule deny-app-to-internet. Check 4 web outbound 8080: Allow, rule allow-web-to-app-8080. The rule name may carry a prefix such as securityRules/.

2. **Test with a real connection**: IP flow verify is a calculation. Confirm it with live traffic from web-1.

   ```bash
   az vm run-command invoke -g nsg19-rg -n web-1 --command-id RunShellScript --scripts "curl -s -m 5 http://10.30.2.10:8080; nc -zv -w 3 10.30.2.10 22"
   ```

   Expect: The curl prints `app-1 reached on tcp/8080` (from the listener's page). The nc to port 22 times out: a silent drop, not a refusal.

3. **Checkpoint**: Port 22 had no Allow rule. Which rule made the denial explicit, and what would have happened without it? Answer: deny-vnet-to-app (200). Without it the default AllowVnetInBound (65000) would admit the SSH attempt.

## Activity 4: Add the NIC-level NSG: the second layer

**Goal.** Attach an NSG to app-1's NIC and watch a subnet Allow be overridden by a NIC Deny.

**Exam skill:** Know the evaluation order (subnet then NIC inbound, NIC then subnet outbound) and that both layers must allow.

1. **Open gate 2**: Set `attach_nic_nsg = true` in `terraform.tfvars` (the VMs from Activity 2 must exist).

   ```bash
   terraform plan -out=nic.tfplan
   terraform apply nic.tfplan
   ```

   Expect: Two objects are added: nsg-app-nic and its association with app-1-nic.

2. **Read the effective rules again**: The NIC now has two NSGs.

   ```bash
   az network nic list-effective-nsg -g nsg19-rg -n app-1-nic -o json
   ```

   Expect: Two entries, one for nsg-app (association: subnet) and one for nsg-app-nic (association: network interface). Check the current output format.

3. **Repeat check 1**: The same tuple as Activity 3.

   ```bash
   ./scripts/verify.sh flows
   ```

   Expect: Check 1 is now Deny, naming deny-web-8080-at-nic, although nsg-app still allows it. Detach by setting `attach_nic_nsg = false` and applying to restore Allow.

4. **Optional, gate 5: the layer above the NSG**: Setting `enable_avnm_demo = true` creates a Virtual Network Manager with one security admin rule (Deny inbound tcp/23 from the Internet) and deploys it to the lab VNet. Read the plan twice: a deployed configuration affects every VNet in its network group. In the portal open app-1-nic, then Effective security rules.

   Expect: Security admin rules appear in their own list, above the NSG rules. They are not shown by `az network nsg rule list`. IP flow verify may not evaluate them; check current docs. This step is designed, not tested, and the Terraform resource names were not validated.

5. **Checkpoint**: Both NSGs use priority 100. Why do they not conflict? Answer: priorities only order the rules inside one NSG. Each NSG is evaluated as its own list and the packet must be allowed by every NSG on the path.

## Activity 5: Change ASG membership and read a service tag rule

**Goal.** Remove web-1 from asg-web and see the ASG rules stop matching, then test a Storage tag rule.

**Exam skill:** Explain how ASGs and service tags change what a rule matches without editing the rule.

1. **Remove the NIC from the ASG**: Set `web_nic_in_asg = false` and apply. Only the membership changes; no rule is edited.

   ```bash
   terraform plan -out=asg.tfplan
   terraform apply asg.tfplan
   ```

   Expect: One object is destroyed: the association of web-1-nic with asg-web.

2. **Repeat check 1**: Same tuple, new membership.

   ```bash
   ./scripts/verify.sh flows
   ```

   Expect: Check 1 is now Deny by deny-vnet-to-app: rule 100 no longer matches the source because web-1's NIC is not in asg-web. Set `web_nic_in_asg = true` and apply to restore it.

3. **Pick a real prefix from the Storage tag**: Service tag contents are Microsoft's; the lab examples use documentation addresses, so you need a real one for a test.

   ```bash
   az network list-service-tags --location westeurope --query "values[?name=='Storage.WestEurope'].properties.addressPrefixes | [0] | [0]" -o tsv
   ```

   Expect: One IPv4 prefix such as a /23 or /24. Choose any address inside it for the next step. The prefix changes over time; check current output.

4. **Test the outbound rule with that address**: Replace `<STORAGE_IP>` with the address you picked.

   ```bash
   az network watcher test-ip-flow -g nsg19-rg --vm app-1 --nic app-1-nic --direction Outbound --protocol TCP --local 10.30.2.10:49154 --remote <STORAGE_IP>:443
   ```

   Expect: Allow, rule allow-app-to-storage-443 (priority 100). The same address is also in the Internet tag, which proves that the lower priority number decides.

5. **Checkpoint**: The address is in both the Storage tag and the Internet tag. Why is it allowed? Answer: rule 100 (Storage, Allow) is read before rule 4000 (Internet, Deny), and the first match wins.

## Activity 6: Private endpoint: network policies decide whether the NSG applies

**Goal.** Create a blob private endpoint (gate 3), test the NSG rules, then switch network policies off and test again.

**Exam skill:** Explain why an NSG on a private endpoint subnet may do nothing, and how to make it apply.

1. **Open gate 3**: Set `deploy_private_endpoint = true`. Keep `pe_network_policies = "Enabled"`. A storage account and an endpoint bill a small hourly amount.

   ```bash
   terraform plan -out=pe.tfplan
   terraform apply pe.tfplan
   terraform output private_endpoint_ip
   ```

   Expect: About 5 objects are added: nsg-pe with its association, a random suffix, a storage account and the endpoint. The output is the endpoint's private IP (10.30.3.4 is typical for the first address, but read it).

2. **Test from both VMs with policies on**: Replace `<PE_IP>` with the output. `nc` only checks the TCP connect, so DNS is not needed.

   ```bash
   az vm run-command invoke -g nsg19-rg -n app-1 --command-id RunShellScript --scripts "nc -zv -w 3 <PE_IP> 443"
   az vm run-command invoke -g nsg19-rg -n web-1 --command-id RunShellScript --scripts "nc -zv -w 3 <PE_IP> 443"
   ```

   Expect: app-1 connects (rule 100 allow-app-to-pe-443). web-1 times out (rule 200 deny-vnet-to-pe). Policy changes can take a few minutes to apply.

3. **Switch the policies off**: Set `pe_network_policies = "Disabled"` and apply the subnet change.

   ```bash
   terraform plan -out=pe2.tfplan
   terraform apply pe2.tfplan
   ```

   Expect: One object is changed in place: snet-pe.

4. **Repeat the web-1 test**: Same command as step 2, from web-1.

   ```bash
   az vm run-command invoke -g nsg19-rg -n web-1 --command-id RunShellScript --scripts "nc -zv -w 3 <PE_IP> 443"
   ```

   Expect: web-1 now connects: the NSG is no longer applied to the endpoint. Set the policies back to `Enabled`. The exact values and their effect on UDRs are in the current Azure docs.

5. **Checkpoint**: web-1 reached an endpoint that an NSG denies. What is the first thing to check? Answer: the network policies setting on the endpoint's subnet.

## Activity 7: Read the flow logs, then clean up

**Goal.** Turn on a virtual network flow log (gate 4), find your own connections in it, then destroy the lab.

**Exam skill:** Read flow tuple fields (decision, direction, state) and know the retirement of NSG flow logs.

1. **Open gate 4**: Set `enable_flow_logs = true`. It needs the regional Network Watcher, which Azure normally creates for you in `NetworkWatcherRG`. Check the provider docs: the flow log resource and its attribute names changed with the NSG flow log retirement.

   ```bash
   terraform plan -out=fl.tfplan
   terraform apply fl.tfplan
   terraform output flow_log_storage_account
   ```

   Expect: A storage account and a flow log are added. The output is the account name.

2. **Generate known traffic**: Repeat one allowed and one denied connection from web-1.

   ```bash
   az vm run-command invoke -g nsg19-rg -n web-1 --command-id RunShellScript --scripts "curl -s -m 5 http://10.30.2.10:8080; nc -zv -w 3 10.30.2.10 22"
   ```

   Expect: One success and one timeout. Flow log blobs appear after a few minutes.

3. **Find the blobs**: Replace `<ACCOUNT>` with the output. The container name for virtual network flow logs is shown below; NSG flow logs used a different one.

   ```bash
   az storage blob list --account-name <ACCOUNT> --container-name insights-logs-flowlogflowevent --auth-mode login --query "[].name" -o tsv
   ```

   Expect: A path ending in a PT1H.json file for the current hour. Your account needs a data role such as Storage Blob Data Reader.

4. **Read two tuples**: Download one blob and look for `10.30.2.10`. See `queries/flowlog-blob-fields.md` for the NSG version 2 field order.

   Expect: An allowed entry (decision A) for port 8080 and a denied entry (decision D or its equivalent in the virtual network flow log format) for port 22. The layouts differ between flow log types; check the current docs.

5. **Clean up**: Destroy the whole lab through your approved workflow, then confirm the group is gone.

   ```bash
   terraform destroy
   az group exists -n nsg19-rg
   ```

   Expect: Destroy complete. `az group exists` prints `false`. If you used gate 5, destroy it first so the security admin configuration is removed from the VNet.

6. **Checkpoint**: Which direction does an inbound flow log entry use, and what does state E mean? Answer: direction I; state E is the end of the flow.
