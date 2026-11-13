# Lab guide: Azure DNS and private DNS zones

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false` and `break_fix` defaults to `none`. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, defaults and attribute names.

## Activity 1: Plan the free baseline and read the links

**Goal.** Create the free DNS objects and read the two links: one with registration, one without.

**Exam skill:** Tell a registration link from a resolution link, and know that neither is a peering.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false` and `break_fix` stays `none`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 12 objects: 1 resource group, 2 VNets, 4 subnets, 1 private zone, 2 links and 2 records. No VM, no endpoint, no storage account. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost; private zones and queries are billed by Azure DNS pricing, so check current prices.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The outputs show `resource_group` and `private_zone`.

3. **Read the links of the private zone**: The helper wraps `az network private-dns link vnet list`.

   ```bash
   ./scripts/diagnose.sh links
   ```

   Expect: Two rows for lab20.example: link-app with registration `True` and link-spoke with registration `False`, both with state `Completed`. The Private Link zone does not exist yet.

4. **Read the records**: Only static records exist so far.

   ```bash
   ./scripts/diagnose.sh records
   ```

   Expect: An SOA, `www` (A, 300) and `api` (A, 30). No VM record yet, because no VM exists.

5. **Checkpoint**: Which link can write records, and does either link make the two VNets reach each other? Answer: link-app (registration enabled) writes the VMs' records. Neither link carries traffic: VNets are not peered in this lab.

## Activity 2: Deploy the VMs and watch autoregistration

**Goal.** Add the two VMs (gate 1), see one record appear by itself, and resolve names from both VNets.

**Exam skill:** Know that only the registration link creates records, and that a resolution link still reads them.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_vms = true` and paste your public key text into `admin_ssh_public_key`. The VMs bill by the hour until destroyed.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: 4 objects are added: 2 NICs and 2 Linux VMs. The output `vm_names` lists vm-app-1 and vm-spoke-1.

2. **Read the records again**: Wait a minute after the VM is running.

   ```bash
   ./scripts/diagnose.sh records
   ```

   Expect: A new row `vm-app-1` (A, 10.40.1.10) with a very short TTL. There is no row for vm-spoke-1, because its VNet has only a resolution link.

3. **Resolve both names from both VMs**: The helper runs the lab's DNS client through the Azure agent, asking 168.63.129.16.

   ```bash
   ./scripts/diagnose.sh query vm-app-1.lab20.example
   ./scripts/diagnose.sh query vm-spoke-1.lab20.example
   ```

   Expect: The first name gives `NOERROR` and A 10.40.1.10 from both VMs. The second gives `NXDOMAIN` from both, because the zone matches but holds no record for vm-spoke-1.

4. **Confirm which resolver the VM uses**: Run-command goes through the Azure agent, not through any network path.

   ```bash
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "resolvectl status | head -15"
   ```

   Expect: The link eth0 shows `DNS Servers: 168.63.129.16` (Azure-provided DNS). The exact layout depends on the image.

5. **Checkpoint**: Why does vm-spoke-1 resolve vm-app-1 but never appears in the zone itself? Answer: link-spoke is a resolution link (read only). Only a registration link writes records, and a VNet may have only one registration-enabled zone link.

## Activity 3: Remove the link and read what the VM sees

**Goal.** Leave out the spoke link with `break_fix`, watch the private names vanish, and restore them.

**Exam skill:** Diagnose a missing link: the VM asks the right resolver, and the zone simply never answers.

1. **Break it**: The selector removes only `link-spoke`.

   ```bash
   terraform apply -var 'break_fix=no_spoke_link'
   ```

   Expect: 1 object is destroyed: `azurerm_private_dns_zone_virtual_network_link.spoke[0]`. Read the plan first.

2. **Ask for the static name**: `www` is a static record (10.40.1.10), so it works for any linked VNet.

   ```bash
   ./scripts/diagnose.sh query www.lab20.example
   ```

   Expect: vm-app-1: `NOERROR`, A 10.40.1.10, TTL 300 or less. vm-spoke-1: `NXDOMAIN`, no records, because no zone with this suffix is linked to its VNet and public DNS does not know the name.

3. **Prove it with the links**: Do not guess; list them.

   ```bash
   ./scripts/diagnose.sh links
   ```

   Expect: Only link-app is listed for lab20.example.

4. **Fix it and read again**: Setting the selector back recreates the link. A client may cache the failed answer for a short time, so retry after a minute.

   ```bash
   terraform apply -var 'break_fix=none'
   ./scripts/diagnose.sh query www.lab20.example
   ```

   Expect: Both VMs return A 10.40.1.10 again. If vm-spoke-1 still fails for a minute, that is the negative cache; check current docs for the timers.

5. **Checkpoint**: The same NXDOMAIN can have two causes. Name them. Answer: the link is missing (no zone matches, public DNS says no), or the link exists but the record is missing (the zone matches and says no). The link list tells them apart.

## Activity 4: Private endpoint DNS: the CNAME chain, then two ways to break it

**Goal.** Create a blob private endpoint (gate 3), read the chain, then break it by an unlinked zone and by a missing zone group.

**Exam skill:** Explain why a linked privatelink zone turns a public name into a private IP, and what each missing piece does.

1. **Open gate 3**: Set `deploy_private_endpoint = true` in `terraform.tfvars`. A storage account, a blob endpoint, a zone and two links are created.

   ```bash
   terraform plan -out=pe.tfplan
   terraform apply pe.tfplan
   terraform output blob_host_name
   ```

   Expect: About 7 objects are added: a random suffix, a storage account, a private zone, two links, an endpoint (with its zone group). The output is `<account>.blob.core.windows.net`.

2. **Resolve the blob name from both VMs**: Replace `<BLOB_HOST>` with the output. Note the order of the records in the answer.

   ```bash
   ./scripts/diagnose.sh query <BLOB_HOST>
   ```

   Expect: NOERROR with a CNAME to `<account>.privatelink.blob.core.windows.net` and then an A record, 10.40.2.4 or the first free address in snet-pe, from both VMs. The chain is the whole point of the activity.

3. **Read the privatelink zone**: The zone group wrote the record; you did not.

   ```bash
   ./scripts/diagnose.sh records
   ```

   Expect: The privatelink zone has an A record named after the storage account, pointing at the endpoint's private IP.

4. **Break it: unlink the spoke**: The selector leaves out only the spoke's link to the privatelink zone.

   ```bash
   terraform apply -var 'break_fix=pe_zone_unlinked'
   ./scripts/diagnose.sh query <BLOB_HOST>
   ```

   Expect: vm-app-1 still gets the private IP. vm-spoke-1 now gets the CNAME chain ending in a public IP address of the storage service. The name works and goes the wrong way.

5. **Break it differently: no zone group**: The endpoint is updated so nothing writes the record. (The A record is removed with the zone group; check the plan.)

   ```bash
   terraform apply -var 'break_fix=no_zone_group'
   ./scripts/diagnose.sh records
   ./scripts/diagnose.sh query <BLOB_HOST>
   ```

   Expect: The privatelink zone has no A record. Both VMs get `NXDOMAIN` after the CNAME: the zone is linked and matches, but is empty. Compare with step 4, which returned a public IP.

6. **Restore**: Set the selector back and apply.

   ```bash
   terraform apply -var 'break_fix=none'
   ```

   Expect: The zone group and the spoke link return, and the record is written again.

7. **Checkpoint**: Unlinked zone gives a public IP; linked but empty zone gives NXDOMAIN. Why the difference? Answer: with no link, no zone matches and recursion reaches public DNS. With a link, the zone matches and is authoritative, so a missing record is final.

## Activity 5: Custom DNS server: forward to 168.63.129.16, or lose the private zones

**Goal.** Point the app VNet at a forwarder (gate 2), prove it works, then break its upstream.

**Exam skill:** Know that a custom DNS server inside the VNet must forward to 168.63.129.16 to see linked private zones.

1. **Open gate 2**: Set `deploy_custom_dns = true`. This adds the dns-fwd VM and changes the DNS server setting of vnet-app. Running VMs pick it up at their next DHCP renewal, so restart vm-app-1 to be sure.

   ```bash
   terraform plan -out=dns.tfplan
   terraform apply dns.tfplan
   az vm restart -g dns20-rg -n vm-app-1
   ```

   Expect: 2 objects are added (NIC and VM for dns-fwd) and the VNet is updated in place. After the restart, `resolvectl status` on vm-app-1 shows `DNS Servers: 10.40.3.10`.

2. **Check the VNet setting**: An empty list means Azure-provided DNS.

   ```bash
   ./scripts/diagnose.sh vnetdns
   ```

   Expect: vnet-app lists `10.40.3.10`. vnet-spoke lists nothing, so it keeps using Azure-provided DNS.

3. **Resolve through the forwarder**: The forwarder is the working design: its upstream is 168.63.129.16.

   ```bash
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "python3 /opt/lab/dnsq.py www.lab20.example 10.40.3.10; python3 /opt/lab/dnsq.py vm-app-1.lab20.example"
   ```

   Expect: Both answers are `NOERROR` with 10.40.1.10. The first one went vm-app-1 to dns-fwd to 168.63.129.16.

4. **Break it: forward to a public resolver**: Changing the upstream changes the VM's custom data, so Terraform replaces dns-fwd (a few minutes). Read the plan.

   ```bash
   terraform apply -var 'break_fix=public_forwarder'
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "python3 /opt/lab/dnsq.py www.lab20.example 10.40.3.10; python3 /opt/lab/dnsq.py www.lab20.example 168.63.129.16"
   ```

   Expect: Through 10.40.3.10: `NXDOMAIN` (a public resolver does not know the private zone), or a timeout if the VM has no outbound path. Directly through 168.63.129.16: `NOERROR` and 10.40.1.10. Two resolvers, two answers: that is the diagnosis.

5. **Restore**: Set the selector back so the forwarder is replaced again.

   ```bash
   terraform apply -var 'break_fix=none'
   ```

   Expect: dns-fwd is recreated with upstream 168.63.129.16.

6. **Checkpoint**: Why can the forwarder not ask the private zone itself? Answer: zone data is served only by 168.63.129.16 to VMs in linked VNets. A forwarder in a linked VNet forwards to it; a server outside Azure cannot reach it at all.

## Activity 6: Stale record and TTL: the zone is right, the client is not

**Goal.** Publish a wrong record with a long TTL, fix it, and watch the old answer linger.

**Exam skill:** Separate a wrong record from a cached record, and know that TTL controls how long a wrong answer lives.

1. **Publish the stale record**: The selector points `api` at 10.40.1.99 with a one hour TTL.

   ```bash
   terraform apply -var 'break_fix=stale_record'
   ./scripts/diagnose.sh query api.lab20.example
   ```

   Expect: A 10.40.1.99, TTL 3600 or counting down from it, from both VMs. Nothing owns that address.

2. **Cache it in the guest**: The resolver in the guest caches the answer for its TTL.

   ```bash
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "resolvectl query api.lab20.example"
   ```

   Expect: The guest answer shows 10.40.1.99. Keep this open in your notes.

3. **Fix the record**: The selector back to `none` rewrites `api` to 10.40.1.10 with a 30 second TTL.

   ```bash
   terraform apply -var 'break_fix=none'
   ./scripts/diagnose.sh records
   ```

   Expect: The record set `api` now shows 10.40.1.10 and TTL 30.

4. **Ask again from the guest**: The guest cache and the platform cache may still hold the old value. The exact caching depends on the image and the platform; check current docs.

   ```bash
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "resolvectl query api.lab20.example"
   ```

   Expect: Possibly still 10.40.1.99: the zone is right and the client is stale. A direct query to 168.63.129.16 may also return the old value until its cached copy expires.

5. **Flush the guest cache**: Clearing only the guest's cache shows which cache is the culprit.

   ```bash
   az vm run-command invoke -g dns20-rg -n vm-app-1 --command-id RunShellScript --query "value[0].message" -o tsv --scripts "sudo resolvectl flush-caches; resolvectl query api.lab20.example"
   ```

   Expect: 10.40.1.10 if the platform cache already expired or never held it. Otherwise wait for the TTL. Lowering a TTL before a planned change is the real fix.

6. **Checkpoint**: The TTL was 3600 and you fixed the record at once. When does every client see the fix? Answer: after the longest remaining TTL among the caches, up to an hour here. Lower the TTL well before a planned change.

## Activity 7: Split-horizon with a public zone, then clean up

**Goal.** Add a public zone with the same name (gate 4), see two answers for one name, then destroy the lab.

**Exam skill:** Explain split-horizon, and that a name that exists only in the public zone returns NXDOMAIN to linked VMs.

1. **Open gate 4**: Set `create_public_zone = true`. The public zone is not delegated, so only a direct query to its name servers reaches it. Public zones are billed per month and per query; check current prices.

   ```bash
   terraform plan -out=pub.tfplan
   terraform apply pub.tfplan
   terraform output public_zone_name_servers
   ```

   Expect: 3 objects are added: the public zone and two A records. The output lists four name servers such as `ns1-xx.azure-dns.com.` (examples).

2. **Ask the public zone from your workstation**: Use one of the listed name servers. If `dig` is missing, use `nslookup www.lab20.example <name server>`.

   ```bash
   dig +short @<NAME_SERVER> www.lab20.example
   dig +short @<NAME_SERVER> only-public.lab20.example
   ```

   Expect: 203.0.113.20 and 203.0.113.30: the public answers.

3. **Ask from the VMs**: Linked VMs get the private zone's answer for the same name.

   ```bash
   ./scripts/diagnose.sh query www.lab20.example
   ./scripts/diagnose.sh query only-public.lab20.example
   ```

   Expect: www: A 10.40.1.10 from both VMs. only-public: `NXDOMAIN` from both. The private zone matches the suffix and has no such record, and the default behaviour does not fall back to the public zone. Check current docs for the fallback-to-internet option.

4. **Clean up in two steps**: Autoregistered records are written by Azure, not Terraform, so remove the VMs first, then destroy the rest. Read each plan.

   ```bash
   terraform apply -var 'deploy_vms=false' -var 'deploy_custom_dns=false'
   terraform destroy
   ```

   Expect: The second command deletes everything Terraform created. If a zone refuses to delete, list its records and remove leftovers, then run destroy again.

5. **Confirm nothing is left**: Group deletion is the last check.

   ```bash
   az group exists -n dns20-rg
   ```

   Expect: Prints `false`.

6. **Checkpoint**: A VM in a linked VNet asks for a name that exists only in the same-named public zone. What does it get and why? Answer: NXDOMAIN, because the private zone matches and is authoritative; add the record to the private zone if the VM needs it.
