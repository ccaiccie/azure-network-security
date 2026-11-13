# Lab guide: Azure Standard Load Balancer in depth

Run the activities in order from the `terraform` folder. **Every command here is designed, not tested:** nothing has been applied to Azure and the expected outputs are design intent. Free by default: the virtual network, subnets, NSG and the internal load balancer have no hourly VM cost, but a Standard load balancer bills for its rules and processed data (check current pricing). Costly: the VMs (hourly) and the public IP and public and global load balancers. All costly parts are behind gates that default to false.

All commands assume `export RG=std-lb-lab` and a key at `~/.ssh/id_ed25519.pub`. Replace both to suit you. The `-var` options are written out in each command so that every apply names the full state it expects. VMs have no public IP, so commands run on them through `az vm run-command`.

## Activity 1: Build the internal load balancer and read its parts

**Goal.** Create the virtual network, the backend subnet with its NSG and the internal Standard load balancer, add two web VMs and a client, then read the frontend, pool, probes and rule back from Azure.

**Exam skill.** Name every part of a load balancer configuration and know that a backend only receives traffic when its probe is Up.

1. **Prepare and check the files (no Azure call)**: From the `terraform` folder. Copy the example variables, put your own subscription id in, then run the local source check.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   python3 -I tests/check_contract.py
   terraform fmt -check -recursive
   terraform init
   terraform validate
   ```

   Expected: `ok: 6 gates default false, break_fix defaults to none, all load balancers are Standard`, then `Success! The configuration is valid.`

2. **Preview and apply the substrate**: All gates are false, so the plan holds the group, the VNet, two subnets, the NSG, the load balancer, its pool, two probes and one rule. An empty pool is allowed.

   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   export RG=std-lb-lab
   ```

   Expected: `Plan: 11 to add, 0 to change, 0 to destroy.` then `Apply complete! Resources: 11 added`.

3. **Add the two web VMs and the client**: Gate 1 adds three small VMs with private IPs only. The two web VMs join the pool through NIC associations.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: The plan adds 8 resources: 3 NICs, 2 pool associations and 3 VMs. Wait two to three minutes for boot.

4. **Read the configuration back from Azure**: The helper script prints the rules, the probes, the pool members and the two metrics that matter.

   ```bash
   chmod +x scripts/lb-diagnose.sh
   ./scripts/lb-diagnose.sh $RG
   ```

   Expected: Designed, not tested: rule `rule-http-80` TCP 80 to 80 with distribution `Default`, probe `probe-tcp-80` interval 5 count 2, two NIC configurations in `pool-web`, and `DipAvailability` near 100 once both VMs are Up.

5. **Send the first requests from the client**: The page names the VM, the local address the request arrived on and the client address.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in 1 2 3 4 5 6; do curl -s -m 3 http://10.23.1.10/; done' --query "value[0].message" -o tsv
   ```

   Expected: Six lines such as `vm-web2 served 10.23.1.5:80 to client 10.23.2.4`. Both `vm-web1` and `vm-web2` should appear. The frontend address 10.23.1.10 never appears in the reply because the backend sees its own address.

**Checkpoint questions.**

- What would you see if both probes were down? *Answer: Every request would time out. The load balancer sends new flows only to instances whose probe is Up, and with an empty healthy set it has nowhere to send them.*
- Which address does the web VM see as the client? *Answer: The client VM's own address, 10.23.2.4. A Standard load balancer is a pass-through device: it does not replace the source address.*

**If it doesn't work.** If the plan asks for a subscription id, you did not edit `terraform.tfvars`. If requests time out right after the apply, the VMs are still booting: wait and read `DipAvailability` again. If the VM create fails on the key, check `admin_ssh_public_key`.

## Activity 2: Distribution: 5-tuple hash and session persistence

**Goal.** Count how 30 new connections spread over two backends, then switch the rule to source-IP persistence and count again.

**Exam skill.** Explain why the default distribution is not round-robin and what source-IP persistence changes.

1. **Count the default distribution**: Each `curl` opens a new connection with a new source port, so the 5-tuple changes every time.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in $(seq 1 30); do curl -s -m 3 http://10.23.1.10/ | cut -d" " -f1; done | sort | uniq -c' --query "value[0].message" -o tsv
   ```

   Expected: Two lines with counts that add up to 30, for example `16 vm-web1` and `14 vm-web2`. The split is a hash result, not an alternating pattern, so it is rarely exactly 15 and 15.

2. **Reuse one connection**: Two URLs in one `curl` command reuse one TCP connection, so both requests have the same 5-tuple.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'curl -s -m 3 http://10.23.1.10/ http://10.23.1.10/ http://10.23.1.10/' --query "value[0].message" -o tsv
   ```

   Expected: Three lines from the same VM, because the whole connection is one flow.

3. **Turn on source-IP persistence**: This changes the rule's distribution mode to a 2-tuple of source and destination address.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var session_persistence=SourceIP -out=tfplan
   terraform apply tfplan
   ```

   Expected: `Plan: 0 to add, 1 to change, 0 to destroy.` The rule `rule-http-80` shows `SourceIP`.

4. **Count again**: The client address is always 10.23.2.4, so the hash input never changes.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in $(seq 1 30); do curl -s -m 3 http://10.23.1.10/ | cut -d" " -f1; done | sort | uniq -c' --query "value[0].message" -o tsv
   ```

   Expected: One line: `30 vm-web1` or `30 vm-web2`. The client is pinned to one backend while that backend stays healthy.

5. **Go back to the default**: Remember to restore the default before the next activity.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: The rule returns to `Default`.

**Checkpoint questions.**

- Does the Default mode guarantee that one client always reaches the same backend? *Answer: No. It keeps one flow (one 5-tuple) on one backend. A new connection from the same client has a new source port and can land elsewhere.*
- When is source-IP persistence a bad idea? *Answer: When many users arrive from one address, for example behind a proxy or a NAT. They all hash to one backend and the others sit idle.*

**If it doesn't work.** If the second count still shows two VMs, confirm the apply finished and read the rule with `./scripts/lb-diagnose.sh $RG`. The change can take a short time to apply.

## Activity 3: Health probes: new flows, existing flows and the NSG

**Goal.** Watch a backend leave rotation when its probe fails, see an established connection survive a total probe failure, and fix a probe that the NSG blocks.

**Exam skill.** State what a failed probe does to new flows and to existing flows, and know why the probe source is not a VNet address.

1. **Fail one backend's service**: Stop the port-80 listener on vm-web1 only. The TCP probe cannot connect, so the instance is marked down after two failed probes.

   ```bash
   az vm run-command invoke -g $RG -n vm-web1 --command-id RunShellScript --scripts 'sudo systemctl stop web@80.service' --query "value[0].message" -o tsv
   ```

   Expected: Wait about 15 seconds.

2. **Count the new flows**: Only the healthy instance should answer now.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in $(seq 1 20); do curl -s -m 3 http://10.23.1.10/ | cut -d" " -f1; done | sort | uniq -c' --query "value[0].message" -o tsv
   ```

   Expected: `20 vm-web2`. Read `DipAvailability` in `./scripts/lb-diagnose.sh $RG`: about 50 while one of two instances is down (check the metric's aggregation in the portal).

3. **Start the service again**: The first successful probe puts the instance back.

   ```bash
   az vm run-command invoke -g $RG -n vm-web1 --command-id RunShellScript --scripts 'sudo systemctl start web@80.service' --query "value[0].message" -o tsv
   ```

   Expected: Both VMs answer again after a few seconds.

4. **Hold one connection open**: In a second terminal, start a client that keeps one TCP connection for about 60 seconds and prints which VM answers. Leave it running.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'python3 - <<PY
   import http.client,time
   c=http.client.HTTPConnection("10.23.1.10",80)
   for i in range(6):
     c.request("GET","/")
     print(c.getresponse().read().decode().strip())
     time.sleep(10)
   PY' --query "value[0].message" -o tsv
   ```

   Expected: A line every 10 seconds, always from the same VM.

5. **Block the probe with the NSG**: While the connection is open, apply the nsg_probe broken setup in the first terminal. A deny-all rule at priority 200 now sits in front of the default AzureLoadBalancer rule.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var break_fix=nsg_probe -out=tfplan
   terraform apply tfplan
   ```

   Expected: Designed, not tested: the held connection keeps answering on a Standard load balancer, while a brand-new `curl` from a third terminal times out. Both probes are failing, so the healthy set is empty.

6. **Diagnose and fix**: Read the effective security rules of a backend NIC, then remove the break.

   ```bash
   az network nic list-effective-nsg -g $RG -n nic-vm-web1 -o table
   ./scripts/lb-diagnose.sh $RG
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var break_fix=none -out=tfplan
   terraform apply tfplan
   ```

   Expected: The effective rules list `deny-all-inbound-hardening` (200) before `AllowAzureLoadBalancerInBound` (65001). After the fix `DipAvailability` returns to about 100.

**Checkpoint questions.**

- A probe fails on one of two backends. What happens to the connections already open to it? *Answer: On a Standard load balancer they continue, and no new flows are sent to that backend. They end when the application, a timeout or a reset ends them.*
- What source address does the probe use, and which NSG rule normally allows it? *Answer: 168.63.129.16. The default inbound rule AllowAzureLoadBalancerInBound at priority 65001 allows it unless a lower-numbered custom rule denies it first.*

**If it doesn't work.** If the held connection ends at once, the backend itself closed it: the lab listener answers HTTP/1.1 with a length, so check the script output for an error. If the `list-effective-nsg` command is slow, wait for the NIC to finish updating.

## Activity 4: HA ports, an inbound NAT rule and floating IP

**Goal.** Add a second frontend with an HA ports rule, add an inbound NAT rule, then switch on floating IP and see the destination address the backend receives.

**Exam skill.** Choose between an ordinary rule, an HA ports rule, a NAT rule and floating IP for a given requirement.

1. **Add the HA ports rule**: Gate 2 adds a second frontend 10.23.1.11 and a rule with protocol All and port 0 on the same pool.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var enable_ha_ports_rule=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: The plan adds a frontend change and one rule.

2. **Test two ports**: Port 8080 has no rule on the main frontend but is covered by the HA ports frontend.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'curl -s -m 3 http://10.23.1.11:8080/; curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://10.23.1.10:8080/' --query "value[0].message" -o tsv
   ```

   Expected: The first command prints a page. The second prints `000`: the main frontend has no rule for 8080, so the connection times out.

3. **Add the inbound NAT rule**: Gate 3 maps frontend TCP 2201 to vm-web1 port 22.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var enable_ha_ports_rule=true -var create_nat_rule=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: A NAT rule `nat-ssh-web1` and one NIC association.

4. **Check the NAT port**: A port check is enough: you reach the SSH daemon of vm-web1, never vm-web2.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'timeout 3 bash -c "</dev/tcp/10.23.1.10/2201" && echo open || echo closed' --query "value[0].message" -o tsv
   ```

   Expected: `open`, because the NAT rule forwards the port to vm-web1 port 22.

5. **Turn on floating IP**: The frontend address is added to the loopback of each web VM by cloud-init, and the rule is set to floating IP. This recreates the web VMs because their boot data changes.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var enable_ha_ports_rule=true -var create_nat_rule=true -var floating_ip=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: The plan replaces vm-web1 and vm-web2 and changes the rule. Wait for the VMs to boot.

6. **Read the destination the backend sees**: With floating IP the backend receives the frontend address, not its own.

   ```bash
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in 1 2 3; do curl -s -m 3 http://10.23.1.10/; done' --query "value[0].message" -o tsv
   ```

   Expected: Lines such as `vm-web1 served 10.23.1.10:80 to client 10.23.2.4`. Without floating IP the same line would show 10.23.1.4 or 10.23.1.5.

**Checkpoint questions.**

- Why must the frontend port equal the backend port when floating IP is on? *Answer: The load balancer does not rewrite the destination, so the packet reaches the guest with the frontend address and port unchanged, and the guest listens there.*
- What would break if the frontend address were not on the guest's loopback? *Answer: The guest would drop the packets, because they are addressed to an IP it does not own, and the probe-passing backends would still return nothing.*

**If it doesn't work.** If requests time out after floating IP, the loopback address is missing: the lab adds it at boot, so recreate the VMs, or run `ip addr show lo` on a web VM. A frontend address added to a NIC on one guest only is the usual real-world mistake. If the HA ports plan fails, check that frontend 10.23.1.11 is free.

## Activity 5: The hairpin limitation and the break/fix drills

**Goal.** Show that a backend VM cannot reach its own internal frontend when the hash picks itself, then diagnose three broken setups from symptoms.

**Exam skill.** Recognise hairpin failure, a probe on the wrong port and an affinity surprise from their symptoms and prove each with metrics and effective rules.

1. **Reset to a clean state**: Put every switch back to its default so the drill starts from a working setup.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -out=tfplan
   terraform apply tfplan
   ```

   Expected: Distribution `Default`, floating IP off, no HA ports rule, no NAT rule.

2. **Hairpin: call the frontend from a backend**: Run the loop on vm-web1, which is itself in the pool. Each connection is hashed to a backend. When it lands on vm-web2 it works; when it lands on vm-web1, the packet would return to its own sender.

   ```bash
   az vm run-command invoke -g $RG -n vm-web1 --command-id RunShellScript --scripts 'for i in $(seq 1 20); do curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://10.23.1.10/; done | sort | uniq -c' --query "value[0].message" -o tsv
   ```

   Expected: Designed, not tested: a mix such as `11 200` and `9 000`. The `000` lines are the connections that hashed to the caller itself.

3. **Drill A: a probe on the wrong port**: Apply probe_port. The probe now targets TCP 8081, where nothing listens.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var break_fix=probe_port -out=tfplan
   terraform apply tfplan
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://10.23.1.10/' --query "value[0].message" -o tsv
   ```

   Expected: `000`: every request times out. Yet a direct request to 10.23.1.4 works. Read `./scripts/lb-diagnose.sh $RG`: probe port 8081 and `DipAvailability` at 0.

4. **Drill B: the NSG blocks the probe**: Apply nsg_probe (activity 3 showed the details). Compare the symptom with drill A: the probe port is right this time.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var break_fix=nsg_probe -out=tfplan
   terraform apply tfplan
   az network nic list-effective-nsg -g $RG -n nic-vm-web2 -o table
   ```

   Expected: The same timeout, but the probe port is 80, and the effective rules show the deny rule at priority 200 ahead of 65001.

5. **Drill C: the affinity surprise**: Apply affinity, then count the spread from the client and from a second source.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var break_fix=affinity -out=tfplan
   terraform apply tfplan
   az vm run-command invoke -g $RG -n vm-client --command-id RunShellScript --scripts 'for i in $(seq 1 20); do curl -s -m 3 http://10.23.1.10/ | cut -d" " -f1; done | sort | uniq -c' --query "value[0].message" -o tsv
   ```

   Expected: One backend takes all 20, and nothing is broken. The rule shows `SourceIP` in the helper output.

6. **Restore**: Return to the default and confirm that the data path is back.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -out=tfplan
   terraform apply tfplan
   ./scripts/lb-diagnose.sh $RG
   ```

   Expected: `VipAvailability` and `DipAvailability` return to about 100.

**Checkpoint questions.**

- Drill A and drill B both time out. What separates them in one command? *Answer: The helper output: probe port 8081 against 80. If the port is right, read the effective NSG rules of the backend NIC for a rule that denies 168.63.129.16 before priority 65001.*
- Why does the hairpin fail only for some connections? *Answer: The hash picks the destination backend. When it picks a different backend the flow works. When it picks the sender, the translated packet arrives with the sender as its own source, which cannot work.*

**If it doesn't work.** If a drill does not behave as described, record the helper output and the effective NSG rules, then check current Microsoft documentation, because this lab was designed and never applied.

## Activity 6: Public frontend and cross-region load balancer (costly, optional)

**Goal.** Put a public Standard load balancer and a global load balancer in front of the same two VMs, and reach them from the Internet.

**Exam skill.** Place a global load balancer over regional load balancers and say what each tier is responsible for.

1. **Create the public frontend**: Gate 4 adds a Standard public IP, a public load balancer and an NSG rule that allows TCP 80 from the Internet. This exposes the lab pages to the Internet while it exists.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var create_public_lb=true -out=tfplan
   terraform apply tfplan
   terraform output public_ip
   ```

   Expected: An address of the form 20.x.x.x (your own value; documentation examples use 203.0.113.x).

2. **Call it from your computer**: The reply shows which VM answered and your own address as the client, because the load balancer keeps the source address.

   ```bash
   PIP=$(terraform output -raw public_ip)
   for i in 1 2 3 4 5 6; do curl -s -m 5 http://$PIP/; done
   ```

   Expected: Lines from both VMs with your public address as the client.

3. **Add the global tier**: Gate 5 adds a Global-tier public IP and a load balancer whose backend is the regional frontend. A global IP can take several minutes to answer.

   ```bash
   terraform apply -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var create_public_lb=true -var create_global_lb=true -out=tfplan
   terraform apply tfplan
   terraform output global_ip
   ```

   Expected: A second public address.

4. **Call the global address**: Requests enter at the global frontend and are passed to the regional frontend, then to a VM.

   ```bash
   GIP=$(terraform output -raw global_ip)
   for i in 1 2 3; do curl -s -m 5 http://$GIP/; done
   ```

   Expected: The same kind of reply, still showing your client address. With only one region behind it you cannot see failover; add a second regional load balancer in another region to test it.

5. **Clean up the costly parts at once**: Destroy everything when you finish; see the clean-up section.

   ```bash
   terraform destroy -var admin_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" -var deploy_vms=true -var create_public_lb=true -var create_global_lb=true
   ```

   Expected: `Destroy complete!` and an empty resource group.

**Checkpoint questions.**

- Where is the client address visible on the backend in this activity? *Answer: In the page: the global tier, like the regional one, keeps the client source address (check current docs for this property).*
- Why is the public frontend free of SNAT here? *Answer: The rule has outbound SNAT disabled, because this lab concerns inbound traffic. Outbound design is a different topic.*

**If it doesn't work.** If the global address does not answer, wait several minutes and check that the regional public frontend answers on its own. The global tier needs a Standard regional public load balancer behind it.
