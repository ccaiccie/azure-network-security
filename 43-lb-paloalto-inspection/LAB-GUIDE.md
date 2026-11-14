# Lab guide: inspecting load balancer traffic with VM-Series

Run the activities in order from the `terraform` folder. **Cost warning:** two VM-Series VMs (and their licence), Standard load balancers, public IPs and two small web VMs bill by the hour; destroy the lab the same day. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply`, no `az` command and no PAN-OS commit was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All gates default to `false`. **You must accept the Marketplace terms yourself** (Activity 2). Never put keys or passwords in a file you share. Addresses such as 203.0.113.80 are documentation examples: your real public frontend address comes from `terraform output public_frontend_ip`.

## Activity 1: Plan the free baseline and read the NSGs and routes

**Goal.** Create only free objects: the hub and app networks, the subnets, the peering, the NSGs and one empty route table. Confirm the peering flags and the NSG rules.

**Exam skill:** Read a peering, a subnet association and an NSG, and explain why a Standard frontend needs an explicit allow.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id` and `mgmt_source_cidr` (your own public address as a /32). Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 23 objects: resource group, 2 VNets, 5 subnets, 2 peerings, 5 NSGs with associations and one allow rule, one route table with its association. No VM, no load balancer, no public IP. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete; the outputs show the resource group name.

3. **Read the peering flags**: Forwarded traffic must be allowed on both sides.

   ```bash
   az network vnet peering list -g cs43-rg --vnet-name cs43-app --query "[].{name:name,fwd:allowForwardedTraffic,gw:useRemoteGateways}" -o table
   ```

   Expect: One row `app-to-hub` with `fwd` True and `gw` False. Repeat on `cs43-hub` for `hub-to-app`.

4. **Read the untrust NSG**: A Standard public IP accepts nothing until an NSG allows it.

   ```bash
   az network nsg rule list -g cs43-rg --nsg-name cs43-nsg-untrust -o table
   ```

   Expect: Rules `allow-http-in` (tcp/80 from Internet) and `allow-lb-probe` (tcp/443 from AzureLoadBalancer).

5. **Checkpoint**: Why does the untrust NSG name the service tag `AzureLoadBalancer` and not an address? Answer: the probe source is 168.63.129.16, which the tag covers, and the tag survives address changes.

## Activity 2: Accept the Marketplace terms, deploy the pair and the load balancers

**Goal.** Open gate 1 to create two VM-Series VMs with three NICs, the public load balancer with its probe and rule, the internal load balancer with HA ports, and make both probes healthy.

**Exam skill:** Explain the three NICs, IP forwarding, the two probes and why both firewalls can look down together.

1. **Accept the Marketplace terms (one time per subscription)**: Review the offer's terms and price first. **This is a legal acceptance on your subscription; do it only if you agree.** Publisher, offer, plan and version are variables; check current Azure Marketplace and Palo Alto Networks documentation.

   ```bash
   az vm image terms show --publisher paloaltonetworks --offer vmseries-flex --plan byol
   # after reading the terms:
   az vm image terms accept --publisher paloaltonetworks --offer vmseries-flex --plan byol
   ```

   Expect: `accepted` becomes true. Alternatively set `accept_marketplace_terms = true` so Terraform creates the agreement (designed, not tested).

2. **Open gate 1**: In `terraform.tfvars` set `deploy_firewalls = true`. Supply the admin password through `TF_VAR_admin_password`, never in a file. Two VMs, a Standard load balancer and public IPs bill by the hour.

   ```bash
   terraform plan -out=fw.tfplan
   terraform apply fw.tfplan
   ```

   Expect: About 26 objects are added: 3 public IPs, 6 NICs, an availability set, 2 VMs, the public LB (rule, probe, outbound rule), the internal LB (HA ports rule, probe) and the routes.

3. **Apply the PAN-OS configuration**: Paste `bootstrap/panos-config.set.txt` into each firewall's CLI in configure mode, or build a bootstrap package. Replace the example values first.

   ```bash
   configure
   # paste the set commands from bootstrap/panos-config.set.txt
   commit
   ```

   Expect: `commit` succeeds on both firewalls; `show interface all` lists ethernet1/1 and ethernet1/2 with DHCP addresses.

4. **Read the probe metric**: Both load balancers must see both firewalls as healthy.

   ```bash
   az monitor metrics list --resource $(terraform output -raw public_lb_id) --metric DipAvailability --interval PT1M --aggregation Average -o table
   ```

   Expect: Values rise to 100 within a few minutes. If one stays at 50, one firewall does not answer: check the NSG, the profile and the route.

5. **Checkpoint**: Why does the lab use two virtual routers? Answer: probes from 168.63.129.16 arrive on two interfaces, and one virtual router can hold only one route for that address.

## Activity 3: Deploy the backends and follow an allowed call

**Goal.** Open gate 2, publish the web tier, call the frontend from your computer, and prove the call with the traffic log, the session table and the web server's log.

**Exam skill:** Read a traffic log line, a session with both address pairs, and explain why the server logs the firewall.

1. **Open gate 2**: Set `deploy_backends = true`. Two small web VMs start a tiny web server at boot; the web internal load balancer gets 10.81.0.10.

   ```bash
   terraform plan -out=web.tfplan
   terraform apply web.tfplan
   ```

   Expect: About 10 objects are added. `terraform output public_frontend_ip` prints 203.0.113.80 style address (your real public IP in practice).

2. **Call the frontend**: From your own computer.

   ```bash
   curl -sS -m 10 http://$(terraform output -raw public_frontend_ip)/
   ```

   Expect: A line such as `lab web-1` or `lab web-2`.

3. **Read the session on the firewall**: The session shows both address pairs.

   ```bash
   show session all filter destination-port 80
   show session id <id>
   ```

   Expect: c2s: your address to the frontend; s2c: the web VM to the trust address 10.80.2.4. State ACTIVE or DISCARD.

4. **Read the traffic log**: In the web interface, Monitor, Traffic.

   ```bash
   (rule eq web-in)
   ```

   Expect: A row with rule `web-in`, application `web-browsing`, source NAT 10.80.2.4, bytes in both directions.

5. **Read the web server's log**: The server logs the firewall, not you.

   ```bash
   az vm run-command invoke -g cs43-rg -n cs43-web-1 --command-id RunShellScript --scripts "journalctl -u labweb -n 5 --no-pager"
   ```

   Expect: Log lines with client 10.80.2.4.

6. **Checkpoint**: Which component hid your address, and which header could bring it back? Answer: the firewall's source NAT; an `X-Forwarded-For` header added by a layer 7 device, or a Gateway Load Balancer.

## Activity 4: Break it on purpose: deny, NSG, floating IP and probe

**Goal.** Reproduce four of the break/fix cases with one change each, read the evidence, and restore the setting.

**Exam skill:** Match a symptom to its evidence: policy deny, IP flow verify, a destination that is the NIC address, and probe status.

1. **Denied by policy**: Add your own public address as the blocked source on both firewalls, then call again.

   ```bash
   set address bad-src ip-netmask <your-public-ip>/32
   set address-group blocklist static bad-src
   commit
   curl -sS -m 10 http://$(terraform output -raw public_frontend_ip)/
   ```

   Expect: The call times out. Traffic log: rule `block-bad-src`, action deny. Remove the address and commit.

2. **NSG without an allow**: Set `nsg_allow_http_inbound = false` and apply.

   ```bash
   terraform apply -var nsg_allow_http_inbound=false
   az network watcher test-ip-flow --direction Inbound --protocol TCP --local <fw1-untrust>:80 --remote <your-ip>:50000 --vm cs43-fw1 -g cs43-rg
   ```

   Expect: The call times out; probes stay healthy; the firewall logs nothing. IP flow verify says Access denied with the rule name. Restore the variable.

3. **Floating IP mismatch**: Set `plb_floating_ip = false` and apply.

   ```bash
   terraform apply -var plb_floating_ip=false
   curl -sS -m 10 http://$(terraform output -raw public_frontend_ip)/
   ```

   Expect: Timeout. The traffic log shows destination 10.80.1.4 and no NAT rule 1. `test nat-policy-match` with the frontend destination still matches, which is the trap. Restore `true`.

4. **Block the probe**: Set `break_probe_block = true` and apply; it adds a deny at priority 90 for the load balancer tag.

   ```bash
   terraform apply -var break_probe_block=true
   az monitor metrics list --resource $(terraform output -raw public_lb_id) --metric DipAvailability --interval PT1M -o table
   ```

   Expect: Probe status falls to 0 within about 10 seconds, and every call times out although both firewalls are healthy. Restore `false`.

5. **Checkpoint**: Which of the four showed nothing in the traffic log, and which showed a deny? Answer: the NSG and probe cases show nothing; the policy case shows a deny; the floating IP case shows an unexpected destination.

## Activity 5: Outbound through the internal load balancer

**Goal.** Send a call from a web server to the Internet through the UDR, the internal load balancer, the firewall and the outbound rule, and read both translations.

**Exam skill:** Explain the default route to the internal LB, the double SNAT and which metric warns of port exhaustion.

1. **Read the routes**: The web NIC must show the default route to the internal load balancer.

   ```bash
   az network nic show-effective-route-table -g cs43-rg -n cs43-web-1-nic -o table
   ```

   Expect: `0.0.0.0/0` next hop type VirtualAppliance, address 10.80.2.10; `10.80.0.0/16` VNet peering.

2. **Call the Internet from web-1**: Use a site you choose; the firewall rule `web-out` allows ssl and web-browsing.

   ```bash
   az vm run-command invoke -g cs43-rg -n cs43-web-1 --command-id RunShellScript --scripts "curl -sS -m 10 -o /dev/null -w '%{http_code}' https://example.com"
   ```

   Expect: HTTP code 200 (or a redirect code). Traffic log: rule `web-out`, source NAT 10.80.1.4.

3. **Read the public address the Internet sees**: Use any service that returns the caller's address.

   ```bash
   az vm run-command invoke -g cs43-rg -n cs43-web-1 --command-id RunShellScript --scripts "curl -sS -m 10 https://api.ipify.org"
   ```

   Expect: The public address of the outbound path, not the web VM and not the firewall's private address.

4. **Read the SNAT metrics**: Used ports should stay well below allocated ports.

   ```bash
   az monitor metrics list --resource $(terraform output -raw public_lb_id) --metric SnatConnectionCount --interval PT1M -o table
   ```

   Expect: Rows for the successful state; a failed state would mean exhaustion.

5. **Checkpoint**: Where are the two translations of this call? Answer: the firewall's dynamic IP and port to 10.80.1.4, then the public load balancer's outbound rule to the frontend address.

## Activity 6: The Gateway Load Balancer variant (optional)

**Goal.** Open gate 3 to chain a second public frontend to a Gateway Load Balancer, apply the VM-Series tunnel settings, and see that the web server logs the real client address.

**Exam skill:** Explain the chain, the two tunnels and why no source NAT or UDR is needed.

1. **Open gate 3**: Set `deploy_gateway_lb = true`. It adds a fourth NIC to each firewall, the gateway, a second public frontend and rule. Check that your VM size supports four NICs. Expect the firewalls to be changed or replaced for the extra NIC, so do it on a fresh lab. The gate also removes the web default route (the chained frontend's replies must leave by their own path), so run Activity 5 first.

   ```bash
   terraform plan -out=gw.tfplan
   terraform apply gw.tfplan
   ```

   Expect: About 16 objects are added; `terraform output gateway_frontend_public_ip` prints the chained address.

2. **Configure the tunnels on the firewalls**: Use `bootstrap/panos-gwlb.set.txt` as a starting point. The ports and identifiers must match the pool. **The PAN-OS lines in that file are placeholders: check the current Palo Alto Networks documentation for the exact commands.**

   ```bash
   configure
   # adapt bootstrap/panos-gwlb.set.txt
   commit
   ```

   Expect: The tunnel interfaces are up and the gateway probe is healthy.

3. **Call the chained frontend**: From your computer.

   ```bash
   curl -sS -m 10 http://$(terraform output -raw gateway_frontend_public_ip)/
   ```

   Expect: A line such as `lab web-1`.

4. **Compare the server's log**: Now the client is visible.

   ```bash
   az vm run-command invoke -g cs43-rg -n cs43-web-1 --command-id RunShellScript --scripts "journalctl -u labweb -n 5 --no-pager"
   ```

   Expect: Your public address appears as the client, where the sandwich showed 10.80.2.4.

5. **Checkpoint**: Why does the reply return through the same firewall without NAT? Answer: the gateway pins both directions of a flow to one pool member through the tunnel identifiers.
