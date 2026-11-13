# Lab guide: Service endpoints, Private Endpoint and Private Link Service

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All five gates default to `false`, the switches default to off and `break_fix` defaults to `none`. A `-var` flag applies to that one command only: switches you leave out return to their defaults. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, defaults and attribute names.

## Activity 1: Plan the free baseline and read the subnet settings

**Goal.** Create the free network objects and read which subnet carries the service endpoint.

**Exam skill:** Know that a service endpoint is a subnet property, and that the endpoint subnet's network policies are a separate setting.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`, every switch stays at its default and `break_fix` stays `none`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 10 objects: 1 resource group, 2 VNets, 5 subnets, 1 NSG and 1 NSG association. No VM, no storage account, no endpoint, no load balancer. (Designed, not tested; the exact count depends on the provider.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The output `resource_group` is `pl27-rg`.

3. **Read the three consumer subnets**: The helper wraps `az network vnet subnet show`.

   ```bash
   ./scripts/diagnose.sh subnets
   ```

   Expect: snet-se lists `Microsoft.Storage` under serviceEndpoints. snet-pe lists no service endpoint and shows its private endpoint network policies value (NetworkSecurityGroupEnabled in the working design). snet-plain lists nothing.

4. **Checkpoint**: Which subnet will be able to use the service endpoint, and does vm-plain-1 in snet-plain get it too? Answer: only snet-se. A service endpoint is enabled per subnet, so a VM in another subnet of the same VNet does not benefit.

## Activity 2: Service endpoint and storage firewall, then leave the door open

**Goal.** Open gates 1 and 2, compare a subnet with the endpoint to one without, read the effective routes, then break the firewall with `public_open`.

**Exam skill:** Explain the route and the identity change of a service endpoint, and why a firewall default action of Allow makes every rule pointless.

1. **Open gates 1 and 2**: In `terraform.tfvars` set `deploy_vms = true`, paste your public key text into `admin_ssh_public_key`, and set `deploy_storage = true`. The VMs bill by the hour until destroyed.

   ```bash
   terraform plan -out=se.tfplan
   terraform apply se.tfplan
   terraform output lab_container_url
   ```

   Expect: About 7 objects are added: 2 NICs, 2 VMs, a random suffix, a storage account and a container. The output is `https://<account>.blob.core.windows.net/labdata?restype=container&comp=list`.

2. **Read the storage firewall**: Do not guess; read it.

   ```bash
   ./scripts/diagnose.sh acct
   ```

   Expect: publicNetworkAccess Enabled, defaultAction Deny, bypass None, one VNet rule for snet-se and no IP rules.

3. **Request the container from both VMs**: Replace `<URL>` with the output. The container allows anonymous listing, so only the firewall decides.

   ```bash
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: vm-se-1: `HTTP 200`. vm-plain-1: `HTTP 403` (error code AuthorizationFailure in the body). Same name, same public IP; the difference is the subnet.

4. **Read the effective routes of vm-se-1**: The endpoint is visible as a route.

   ```bash
   ./scripts/diagnose.sh routes vm-se-1
   ```

   Expect: Besides the VNet route and `0.0.0.0/0 Internet` there are many rows with next hop type `VirtualNetworkServiceEndpoint` for the storage service's address prefixes. vm-plain-1 has no such rows.

5. **Leave the door open**: The selector sets the firewall's default action to Allow, the classic mistake.

   ```bash
   terraform apply -var 'break_fix=public_open'
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: vm-plain-1 now gets `HTTP 200` although it has no endpoint, and so would anyone on the Internet. Read the plan first: one in-place change to the storage account.

6. **Restore**: Set the selector back.

   ```bash
   terraform apply -var 'break_fix=none'
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: `HTTP 403` again. Allow rules mean nothing while the default action is Allow.

7. **Checkpoint**: What did the service endpoint add that the firewall rule needed? Answer: an identity. The rule names a subnet, and only traffic that leaves a subnet with the endpoint carries that subnet's identity; without it the service sees only a public IP.

## Activity 3: Private endpoint: private IP, DNS dependency, NSG and policies

**Goal.** Open gate 3, see the name resolve to the endpoint, then break DNS with `zone_unlinked`, and test an NSG rule with `nsg_ignored`.

**Exam skill:** Explain why a private endpoint works only when the name resolves to its IP, and when an NSG rule on the endpoint subnet is applied.

1. **Open gate 3**: Set `deploy_private_endpoint = true`. It needs gate 2. The endpoint bills by the hour.

   ```bash
   terraform plan -out=pe.tfplan
   terraform apply pe.tfplan
   terraform output blob_private_endpoint_ip
   ```

   Expect: About 3 objects are added: the privatelink zone, one link and the endpoint (its zone group is part of the endpoint). The output is `10.50.2.5` (a static address in this lab).

2. **Resolve and request from both VMs**: Use the host name from `lab_blob_host` for the lookup.

   ```bash
   ./scripts/diagnose.sh resolve vm-plain-1 <BLOB_HOST>
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: The name resolves to 10.50.2.5 from both VMs, and both requests give `HTTP 200`. vm-plain-1 now works without any endpoint on its subnet or any change to the firewall: the connection arrives through the private endpoint.

3. **Read the routes and the connection**: A private endpoint is a /32 route.

   ```bash
   ./scripts/diagnose.sh routes vm-plain-1
   ./scripts/diagnose.sh conns
   ```

   Expect: A row for 10.50.2.5/32 with a next hop type that names the endpoint (shown as `InterfaceEndpoint` at the time of writing). The connection list shows the blob endpoint as Approved.

4. **Break it: unlink the zone**: The selector removes the zone's link to the VNet. Check the plan: one link is destroyed.

   ```bash
   terraform apply -var 'break_fix=zone_unlinked'
   ./scripts/diagnose.sh resolve vm-plain-1 <BLOB_HOST>
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: The name now resolves to a public address. vm-plain-1 gets `HTTP 403` (public path, no rule), vm-se-1 still gets `HTTP 200` (public path, service endpoint rule). The private endpoint is healthy and unused. A resolver may cache the old answer for a short time.

5. **Restore, then test an NSG rule**: Add a rule on snet-pe that denies snet-se, but first turn the network policies off with the selector. Read the plan.

   ```bash
   terraform apply -var 'break_fix=none'
   terraform apply -var 'pe_nsg_deny_se=true' -var 'break_fix=nsg_ignored'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: `HTTP 200` from vm-se-1 although the NSG denies its subnet: with the policies Disabled the rule is not applied to endpoint traffic. Check current Microsoft docs for the exact behaviour.

6. **Turn the policies on**: Selector back to none, the rule stays.

   ```bash
   terraform apply -var 'pe_nsg_deny_se=true' -var 'break_fix=none'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: vm-se-1 now fails: curl times out (`HTTP 000`) because the NSG drops the traffic. vm-plain-1 still gets `HTTP 200`. Policies on means the NSG is evaluated.

7. **Checkpoint**: The endpoint works and the name resolves, yet an NSG deny is ignored. Why? Answer: the subnet's network policies for private endpoints were Disabled, so NSG rules were not applied to the endpoint's traffic. Enable the policies on the endpoint subnet, then the NSG is evaluated.

## Activity 4: Disable public access, then an endpoint that waits for approval

**Goal.** Switch off public network access, watch the service endpoint stop working, then leave the endpoint pending.

**Exam skill:** Explain why public network access Disabled makes service endpoints useless, and diagnose a Pending connection.

1. **Disable public access**: Remove the test NSG rule first to keep the picture clean, then switch public access off.

   ```bash
   terraform apply -var 'pe_nsg_deny_se=false' -var 'disable_public_access=true'
   ./scripts/diagnose.sh acct
   ```

   Expect: publicNetworkAccess Disabled. The firewall rules are still listed but no longer matter.

2. **Request from both VMs**: Both resolve to the private IP, so both still use the endpoint.

   ```bash
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: Both `HTTP 200`: the private endpoint is not affected by the public switch.

3. **Show that the service endpoint is now useless**: Unlink the zone so that vm-se-1 goes to the public name again.

   ```bash
   terraform apply -var 'disable_public_access=true' -var 'break_fix=zone_unlinked'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: `HTTP 403` even though snet-se is a VNet rule and has the endpoint: the public endpoint is off. (Resolver caching may delay the change.)

4. **Break it: a pending endpoint**: The selector makes the connection manual. Terraform replaces the endpoint. Read the plan.

   ```bash
   terraform apply -var 'disable_public_access=true' -var 'break_fix=pe_pending'
   ./scripts/diagnose.sh conns
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: The connection list shows `Pending`. The request fails: `HTTP 000` (timeout) or a reset. The endpoint's NIC and IP exist, but no data flows until the owner approves.

5. **Approve it**: Use the connection name from the list. This is a change; run it through your approved workflow.

   ```bash
   az network private-endpoint-connection approve -g pl27-rg --resource-name <ACCOUNT> --type Microsoft.Storage/storageAccounts -n <CONNECTION> --description approved
   ./scripts/diagnose.sh get vm-plain-1 '<URL>'
   ```

   Expect: The state becomes Approved and the request returns `HTTP 200`. Setting `break_fix=none` instead recreates the endpoint with auto-approval.

6. **Restore**: Public access back on and selector at none.

   ```bash
   terraform apply -var 'break_fix=none' -var 'disable_public_access=false'
   ```

   Expect: The endpoint is recreated if needed and the account is public again, with its firewall at Deny.

7. **Checkpoint**: Why can the endpoint be approved by the same person who creates it in some cases and not in others? Answer: auto-approval needs rights on the target resource and a connection made by resource ID; a manual request (or an alias) always waits for the owner.

## Activity 5: Exfiltration: a service endpoint policy and what a private endpoint does not stop

**Goal.** Add a second account (gate 4), prove that vm-plain-1 can still reach it, then restrict snet-se with a service endpoint policy.

**Exam skill:** Explain what a private endpoint prevents and what it does not, and what a service endpoint policy restricts.

1. **Open gate 4**: Set `deploy_se_policy = true`. The policy is created but not yet attached to snet-se (the switch `attach_se_policy` is false).

   ```bash
   terraform plan -out=sep.tfplan
   terraform apply sep.tfplan
   terraform output other_container_url
   ```

   Expect: About 4 objects are added: the policy, a second resource group, the second account and its container. The output is the second test URL.

2. **Reach the other account from both VMs**: The other account is public with default action Allow, and no policy is attached yet.

   ```bash
   ./scripts/diagnose.sh get vm-plain-1 '<OTHER_URL>'
   ./scripts/diagnose.sh get vm-se-1 '<OTHER_URL>'
   ```

   Expect: Both `HTTP 200`. vm-plain-1 has a private endpoint for the lab account, and that says nothing about other accounts. vm-se-1 reaches the other account over the service endpoint, because a service endpoint opens the whole service type, not one account.

3. **Attach the policy**: The switch attaches the policy to snet-se. Read the plan: one in-place change to the subnet.

   ```bash
   terraform apply -var 'attach_se_policy=true'
   ./scripts/diagnose.sh subnets
   ```

   Expect: snet-se lists the policy id under `policies`. Applying a policy can briefly disturb the subnet's traffic; check current docs.

4. **Ask again**: Same two requests.

   ```bash
   ./scripts/diagnose.sh get vm-se-1 '<OTHER_URL>'
   ./scripts/diagnose.sh get vm-plain-1 '<OTHER_URL>'
   ./scripts/diagnose.sh get vm-se-1 '<URL>'
   ```

   Expect: vm-se-1 to the other account: `HTTP 403`, because the policy allows only storage accounts in the lab resource group over the endpoint. vm-plain-1 to the other account: still `HTTP 200`, because it uses the Internet path, which no endpoint policy covers. vm-se-1 to the lab account: `HTTP 200`.

5. **Checkpoint**: A private endpoint to account A is in place. Can the VM still send data to account B? Answer: yes, unless another control stops it: a service endpoint policy for the service-endpoint path, an NSG or firewall rule for the public path, or no default outbound route at all. The endpoint only decides where its own connection goes.

## Activity 6: Private Link Service: NAT IP, proxy protocol and capacity

**Goal.** Open gate 5, reach the backend through the service, see the NAT IP, then turn on proxy protocol v2.

**Exam skill:** Explain what the provider sees as the client address, and what limits a Private Link Service.

1. **Open gate 5**: Set `deploy_pls = true`. It adds a backend VM, a Standard internal load balancer, the service and a consumer endpoint. Gate 1 must be open to test. All of it bills by the hour.

   ```bash
   terraform plan -out=pls.tfplan
   terraform apply pls.tfplan
   terraform output pls_alias
   terraform output pls_endpoint_ip
   ```

   Expect: About 9 objects are added. The alias looks like `<name>.<guid>.<region>.azure.privatelinkservice` and the endpoint IP is `10.50.2.6`. Wait a few minutes for the backend to boot.

2. **Read the service**: The helper wraps `az network private-link-service show`.

   ```bash
   ./scripts/diagnose.sh pls
   ```

   Expect: One NAT IP (10.60.2.4), proxyProtocol false, the subscription in both the visibility and the auto-approval lists, one connection with status Approved.

3. **Request the service from the consumer**: Port 8080 on the endpoint's IP.

   ```bash
   ./scripts/diagnose.sh body vm-plain-1 http://10.50.2.6:8080/
   ```

   Expect: `backend=vm-backend-1 tcp_peer=10.60.2.4 proxy_src=none link_id=none`. The backend sees the NAT IP, not the consumer.

4. **Turn on proxy protocol v2**: An in-place change to the service.

   ```bash
   terraform apply -var 'enable_proxy_protocol=true'
   ./scripts/diagnose.sh body vm-plain-1 http://10.50.2.6:8080/
   ```

   Expect: `proxy_src=10.50.2.6` (the consumer's endpoint address as documented, not the VM's own IP; check current docs) and a `link_id` value. The TCP peer is still the NAT IP.

5. **Add a NAT IP**: Capacity grows by adding NAT IPs from the /28 subnet.

   ```bash
   terraform apply -var 'enable_proxy_protocol=true' -var 'pls_nat_ip_count=2'
   ./scripts/diagnose.sh pls
   ```

   Expect: Two NAT IPs: 10.60.2.4 and 10.60.2.5. The subnet has 11 usable addresses, but the service allows up to 8 NAT IPs (check current docs), so the service limit comes first.

6. **Checkpoint**: The backend must show the real client for audit. What are the two options and the catch? Answer: proxy protocol v2, which gives the endpoint address and a LinkID (not the consumer VM's own address), and the backend must parse the header or it breaks; or log on the consumer side.

## Activity 7: Consumer approval, then clean up

**Goal.** Leave the consumer request pending with `pls_pending`, approve it, and destroy the lab.

**Exam skill:** Explain visibility, auto-approval and manual approval of a Private Link Service, and tear the lab down in order.

1. **Break it: empty auto-approval list**: The selector empties the list. Terraform updates the service and replaces the consumer endpoint. Read the plan.

   ```bash
   terraform apply -var 'break_fix=pls_pending'
   ./scripts/diagnose.sh pls
   ./scripts/diagnose.sh body vm-plain-1 http://10.50.2.6:8080/
   ```

   Expect: The connection status is `Pending`; the request times out (`curl-failed`). The consumer sees the endpoint with its IP; the provider sees a request waiting.

2. **Approve from the provider side**: The provider owns the decision. Use the connection name from the service output. This is a change.

   ```bash
   az network private-link-service connection update -g pl27-rg --service-name pl27-pls -n <CONNECTION> --connection-status Approved
   ./scripts/diagnose.sh body vm-plain-1 http://10.50.2.6:8080/
   ```

   Expect: The status becomes Approved and the backend answers. (Check the current CLI help for the command name; the portal does the same under the service's private endpoint connections.)

3. **Restore**: Selector back to none and proxy protocol off.

   ```bash
   terraform apply -var 'break_fix=none' -var 'enable_proxy_protocol=false' -var 'pls_nat_ip_count=1'
   ```

   Expect: Auto-approval list restored; one NAT IP.

4. **Clean up**: Read each plan. Set every gate and switch to its default first, then destroy. Storage accounts must be empty of locks; the lab never wrote any blobs.

   ```bash
   terraform apply -var 'deploy_pls=false' -var 'deploy_se_policy=false' -var 'attach_se_policy=false' -var 'deploy_private_endpoint=false' -var 'deploy_vms=false'
   terraform destroy
   ```

   Expect: The destroy deletes everything Terraform created, including the other resource group.

5. **Confirm nothing is left**: Group deletion is the last check.

   ```bash
   az group exists -n pl27-rg
   az group exists -n pl27-other-rg
   ```

   Expect: Both print `false`.

6. **Checkpoint**: A partner in another tenant must connect to your service. Which values do they need and who approves? Answer: the alias (and your approval); their subscription need not be on your visibility list if you use RBAC, but you either list it for auto-approval or approve the pending request by hand.
