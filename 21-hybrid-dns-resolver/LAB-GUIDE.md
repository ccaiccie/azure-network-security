# Lab guide: Hybrid DNS with Azure DNS Private Resolver

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false`. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, pricing, attribute names and the `az dns-resolver` extension.

## Activity 1: Plan the free baseline and read the delegation

**Goal.** Create the free network objects and see that the two resolver subnets are delegated to Microsoft.Network/dnsResolvers.

**Exam skill:** Know the subnet rules for resolver endpoints: one subnet per endpoint, delegated, at least a /28, nothing else inside.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 13 objects: 1 resource group, 3 VNets, 5 subnets and 4 peerings. No resolver, no VM, no storage account. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the outputs `resource_group` and `inbound_endpoint_ip` (10.50.0.4).

3. **Read the delegation of the inbound subnet**: A delegated subnet shows the service that owns it.

   ```bash
   az network vnet subnet show -g dns21-rg --vnet-name dns21-hub -n snet-dns-in --query "{prefix:addressPrefix, delegation:delegations[0].serviceName}" -o json
   ```

   Expect: `addressPrefix` 10.50.0.0/28 and `delegation` Microsoft.Network/dnsResolvers. The same is true for snet-dns-out (10.50.0.16/28). snet-pe has no delegation.

4. **Checkpoint**: Why does the inbound endpoint get 10.50.0.4 and not 10.50.0.1? Answer: Azure reserves the first four addresses (.0 to .3) of every subnet, so the first usable address is .4.

## Activity 2: Deploy the resolver and read its endpoints

**Goal.** Open gate 1 and read the inbound endpoint address and the outbound endpoint state.

**Exam skill:** Tell the inbound endpoint (a listener with an IP) from the outbound endpoint (an exit with no address to point at).

1. **Open gate 1**: In `terraform.tfvars` set `deploy_resolver = true`. The endpoints bill by the hour until destroyed; check current pricing.

   ```bash
   terraform plan -out=resolver.tfplan
   terraform apply resolver.tfplan
   ```

   Expect: About 3 objects are added: the resolver, the inbound endpoint and the outbound endpoint. Creation can take a few minutes.

2. **List both endpoints**: The helper wraps the `az dns-resolver` commands (an Azure CLI extension; check the current name).

   ```bash
   ./scripts/verify.sh objects
   ```

   Expect: The inbound endpoint is Succeeded with a Static address of 10.50.0.4. The outbound endpoint is Succeeded and shows its subnet, but no address to point anything at. The rule and link lists are empty or an error, because gate 2 is still closed.

3. **Try the inbound endpoint from anywhere else**: You have no VM yet, so only read this step. A DNS query sent to 10.50.0.4 from a machine that can route to the hub is answered by Azure DNS in the hub's context.

   Expect: Nothing to run yet. Activity 3 does the real test.

4. **Checkpoint**: Which endpoint would on-premises DNS point a conditional forwarder at? Answer: the inbound endpoint, at 10.50.0.4. The outbound endpoint is only a source of forwarded queries.

## Activity 3: Add the VMs and the ruleset, then resolve a corp name

**Goal.** Show that a spoke VM cannot resolve files.corp.example.com until the ruleset exists and is linked.

**Exam skill:** Predict NXDOMAIN without a ruleset and the on-premises answer with one, and name the path the query takes.

1. **Open gate 3 (VMs)**: Set `deploy_vms = true` and paste your public key text into `admin_ssh_public_key`. The three VMs bill by the hour.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: About 8 objects are added: 3 NICs, 3 VMs and the DNS setting of the onprem VNet (10.60.1.10). Wait a minute for cloud-init to install dnsmasq and dig.

2. **Ask before the ruleset exists**: `run-command` goes through the Azure agent, not through the DNS path.

   ```bash
   az vm run-command invoke -g dns21-rg -n spoke-vm --command-id RunShellScript --scripts "dig +time=3 +tries=1 files.corp.example.com | grep -E 'status|ANSWER SECTION' -A1"
   ```

   Expect: `status: NXDOMAIN`. Azure-provided DNS has no rule for corp.example.com and no public record exists.

3. **Open gate 2 (ruleset)**: Set `deploy_ruleset = true`. The plan adds the ruleset, two rules and two VNet links.

   ```bash
   terraform plan -out=ruleset.tfplan
   terraform apply ruleset.tfplan
   ```

   Expect: About 5 objects: the ruleset, rules `corp-to-onprem` and `old-corp-disabled`, and links `link-spoke` and `link-hub`.

4. **Ask again**: The helper runs the first two queries.

   ```bash
   ./scripts/verify.sh queries
   ```

   Expect: Query 1 (spoke-vm) prints 10.60.1.30, forwarded through the outbound endpoint. Query 2 (onprem-client) prints 10.60.1.30 straight from onprem-dns. Replies cached by a resolver may keep an old NXDOMAIN for a short time; wait for the TTL and retry.

5. **Checkpoint**: Why did the first query work only after the ruleset was linked? Answer: a ruleset only applies to VNets it is linked to; the spoke needed link-spoke before the rule could match.

## Activity 4: Resolve a private endpoint name from on-premises, the spoke and the centralized spoke

**Goal.** Add a private endpoint and see which clients get its private address, and why.

**Exam skill:** Explain that the privatelink zone linked only to the hub is reached through the inbound endpoint, and that a spoke with Azure-provided DNS does not see it.

1. **Open gate 4**: Set `deploy_private_endpoint = true`. The plan adds a storage account, the privatelink zone, a link to the hub, an endpoint and a zone group.

   ```bash
   terraform plan -out=pe.tfplan
   terraform apply pe.tfplan
   terraform output -raw storage_account_fqdn
   ```

   Expect: About 6 objects. The output prints a name like `dns21st1a2b3c.blob.core.windows.net` (your suffix differs). Set it as `SA_FQDN` for the next steps.

2. **Ask from on-premises**: onprem-client asks onprem-dns, which forwards `blob.core.windows.net` to the inbound endpoint.

   ```bash
   export SA_FQDN=<the output>
   ./scripts/verify.sh queries
   ```

   Expect: Query 3 (onprem-client) prints a CNAME to the privatelink name and an A record in 10.50.2.0/24, typically 10.50.2.4.

3. **Ask from the spoke**: Query 4 uses the spoke's Azure-provided DNS.

   ```bash
   ./scripts/verify.sh zone
   ```

   Expect: Query 4 (spoke-vm) prints a **public** address, because the zone is linked only to the hub and the spoke asks its own Azure DNS. The zone listing shows one A record for the account in 10.50.2.0/24.

4. **Centralize the spoke**: Set `spoke_uses_inbound_dns = true` and apply. The VM picks up the new DNS server when its network settings renew; a restart makes it certain.

   ```bash
   terraform apply -var spoke_uses_inbound_dns=true
   az vm restart -g dns21-rg -n spoke-vm
   ./scripts/verify.sh queries
   ```

   Expect: Query 4 now prints the private address. Query 1 still prints 10.60.1.30, as long as the hub is linked to the ruleset (rules apply to queries that reach the inbound endpoint; check current docs).

5. **Checkpoint**: Which setting made the spoke see the hub's zone? Answer: the spoke's DNS server setting, now 10.50.0.4, so its queries are resolved in the hub's context where the zone is linked.

## Activity 5: Break the ruleset: remove the link, then use a wrong target

**Goal.** Reproduce two failures by changing one setting each and read the difference between NXDOMAIN and a timeout.

**Exam skill:** Tell an unlinked ruleset (NXDOMAIN) from a wrong forward target (timeout or SERVFAIL).

1. **Set the spoke back to Azure-provided DNS**: So the failures below come from the ruleset, not from the spoke's DNS server setting.

   ```bash
   terraform apply -var spoke_uses_inbound_dns=false
   az vm restart -g dns21-rg -n spoke-vm
   ```

   Expect: The spoke's DNS server list is empty again (Azure-provided).

2. **Remove the spoke's link**: One switch, one object removed.

   ```bash
   terraform apply -var link_spoke_to_ruleset=false
   ./scripts/verify.sh queries
   ```

   Expect: Query 1 (spoke-vm) returns NXDOMAIN. Query 2 (onprem-client) still works. The destroyed object is `link-spoke` only.

3. **Restore the link and break the target**: A rule that matches but points at an address where nothing listens.

   ```bash
   terraform apply -var link_spoke_to_ruleset=true -var corp_forward_target=10.60.1.11
   ./scripts/verify.sh queries
   ```

   Expect: Query 1 takes several seconds, then fails with SERVFAIL or a timeout. This is not NXDOMAIN: no server answered at all.

4. **Restore the right target**: Return both switches to their defaults.

   ```bash
   terraform apply -var corp_forward_target=10.60.1.10
   ./scripts/verify.sh queries
   ```

   Expect: Query 1 prints 10.60.1.30 again.

5. **Checkpoint**: How do NXDOMAIN and a timeout differ in meaning? Answer: NXDOMAIN means a server answered that the name does not exist; a timeout or SERVFAIL means no server gave a usable answer.

## Activity 6: Break on-premises: a forwarder for the wrong name, then a loop

**Goal.** Reproduce the public-IP answer and the DNS loop by editing the on-premises server, then repair both.

**Exam skill:** Choose the right zone name for a conditional forwarder and recognise a loop from its symptoms.

1. **Forward the privatelink name instead**: This edits dnsmasq on onprem-dns through the Azure agent. Clients still ask for the public name.

   ```bash
   az vm run-command invoke -g dns21-rg -n onprem-dns --command-id RunShellScript --scripts 'sed -i "s#server=/blob.core.windows.net/#server=/privatelink.blob.core.windows.net/#" /etc/dnsmasq.d/lab.conf && systemctl restart dnsmasq'
   ./scripts/verify.sh queries
   ```

   Expect: Query 3 (onprem-client) now prints a public address. DNS answered; the answer is wrong for the design.

2. **Repair the forwarder**: Put the public zone name back.

   ```bash
   az vm run-command invoke -g dns21-rg -n onprem-dns --command-id RunShellScript --scripts 'sed -i "s#server=/privatelink.blob.core.windows.net/#server=/blob.core.windows.net/#" /etc/dnsmasq.d/lab.conf && systemctl restart dnsmasq'
   ```

   Expect: Query 3 prints the private address again. The restart also empties dnsmasq's cache.

3. **Create a loop**: Add a forwarder that is too wide: everything under example.com goes to the inbound endpoint.

   ```bash
   az vm run-command invoke -g dns21-rg -n onprem-dns --command-id RunShellScript --scripts 'echo server=/example.com/10.50.0.4 >> /etc/dnsmasq.d/lab.conf && systemctl restart dnsmasq'
   az vm run-command invoke -g dns21-rg -n onprem-client --command-id RunShellScript --scripts "dig +time=5 +tries=1 missing.corp.example.com | grep status"
   ```

   Expect: `files.corp.example.com` still works (it is answered locally) but `missing.corp.example.com` fails with SERVFAIL or a timeout instead of NXDOMAIN. The exact failure depends on timers.

4. **Repair the loop**: Remove the wide forwarder.

   ```bash
   az vm run-command invoke -g dns21-rg -n onprem-dns --command-id RunShellScript --scripts 'sed -i "/^server=\/example.com\//d" /etc/dnsmasq.d/lab.conf && systemctl restart dnsmasq'
   ```

   Expect: `missing.corp.example.com` returns NXDOMAIN quickly again.

5. **Checkpoint**: Which side should own corp.example.com in this lab, and what breaks the loop? Answer: on-premises owns it. Azure forwards it there and on-premises answers locally; a forwarder that sends any part of that name back to Azure closes the loop.

## Activity 7: Collect evidence and clean up

**Goal.** Save the evidence you need, then destroy every gated stage and confirm nothing remains.

**Exam skill:** Know the order of removal and that closing a gate destroys that stage.

1. **Save the evidence**: Save the outputs of the helper before you destroy anything.

   ```bash
   ./scripts/verify.sh objects > evidence-objects.txt
   ./scripts/verify.sh queries > evidence-queries.txt
   ```

   Expect: Two text files with the endpoints, rules, links and the four query answers.

2. **Destroy the whole lab**: Through your approved workflow. The resolver's endpoints stop billing when destroyed.

   ```bash
   terraform destroy
   ```

   Expect: Destroy complete. If a stage fails because of a dependency, destroy it first with its gate set to false, then run `terraform destroy` again.

3. **Confirm nothing remains**: A deleted group is the final proof.

   ```bash
   az group exists -n dns21-rg
   ```

   Expect: Prints `false`.

4. **Checkpoint**: Which objects keep billing if you only delete the VMs? Answer: the resolver endpoints (per hour) and any storage account; delete the stages, not only the VMs.
