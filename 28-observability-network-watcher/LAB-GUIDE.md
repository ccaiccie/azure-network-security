# Lab guide: network observability with Network Watcher

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses are RFC 1918 examples. Check current Microsoft docs for limits, retirement dates, table and column names, pricing and provider argument names.

## Activity 1: Plan the free baseline and find Network Watcher

**Goal.** Create the free VNets, peerings and NSG, confirm that the regional Network Watcher already exists, and draw the topology.

**Exam skill:** Know that Network Watcher is a per-region resource that Azure normally creates for you, and that topology is a map, not packet evidence.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 9 objects: 1 resource group, 2 VNets, 2 subnets, 1 NSG, 1 NSG association and 2 peerings. No VM, no workspace. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the outputs `resource_group`, `vnet_ids` and `network_watcher`.

3. **Find the regional Network Watcher**: Azure normally creates one per region in `NetworkWatcherRG`. The lab reads it instead of creating a second one.

   ```bash
   az network watcher list -o table
   ```

   Expect: A row named NetworkWatcher_westeurope in NetworkWatcherRG. If there is none, set `create_network_watcher = true` and plan again.

4. **Draw the topology**

   ```bash
   ./scripts/netwatch-check.sh topology
   ```

   Expect: JSON that lists the two VNets, their subnets, the NSG and the peerings. The portal draws the same data as a diagram. Check current docs if the command is not available in your CLI version.

5. **Checkpoint**: Why does the lab not create a Network Watcher by default? Answer: there is normally one per region already, and a second one in the same region is not allowed, so the lab reads the existing one.

## Activity 2: Configuration tools: effective routes, next hop and IP flow verify

**Goal.** Open gate 1, then use effective routes, next hop, effective security rules and IP flow verify to read what the network says without sending traffic.

**Exam skill:** Choose between effective routes (the whole table) and next hop (one destination), and use IP flow verify to name the NSG rule that decides a packet.

1. **Open gate 1 and plan**: Set `deploy_vms = true` and `admin_ssh_public_key = "<text of your public key>"`. The VMs bill by the hour.

   ```bash
   terraform plan -out=vms.tfplan
   terraform apply vms.tfplan
   ```

   Expect: 6 objects: 2 NICs, 2 VMs and 2 Network Watcher agent extensions. (Designed, not tested.)

2. **Ask the next hop**: From vm-client to the server address. There is no firewall yet.

   ```bash
   ./scripts/netwatch-check.sh nexthop
   ```

   Expect: A next hop type for the peering (the wording may be VnetLocal or VNet peering depending on the tool) and no route table: the system route.

3. **Read all the routes**

   ```bash
   ./scripts/netwatch-check.sh routes
   ```

   Expect: The client lists 10.80.0.0/24 (VNet local), 10.81.0.0/24 (VNet peering) and 0.0.0.0/0 (Internet). Source Default, state Active.

4. **Read the effective security rules**

   ```bash
   ./scripts/netwatch-check.sh rules
   ```

   Expect: On vm-server-nic: rule app-port (priority 100, Allow, TCP 8080 from 10.80.0.0/24) and the default rules AllowVnetInBound, AllowAzureLoadBalancerInBound and DenyAllInBound.

5. **Verify two packets with IP flow verify**: The helper asks twice: from the client and from an address outside the VNets (a documentation range).

   ```bash
   ./scripts/netwatch-check.sh ipflow
   ```

   Expect: The client packet: Access Allowed, rule app-port. The outside packet: Access Denied, rule DenyAllInBound.

6. **Call the page and ping**

   ```bash
   ./scripts/netwatch-check.sh app
   ```

   Expect: The curl prints 200 and ping shows replies.

7. **Checkpoint**: IP flow verify said Allowed, rule app-port. Does that prove the page will load? Answer: no. It checks only the NSG rules for one packet, not routes, a firewall or a listener. The curl in step 6 is the proof.

## Activity 3: Ping works, TCP fails: find the rule with one command

**Goal.** Flip the NSG switch so that the application port is denied, watch ping keep working while the page fails, and name the rule with IP flow verify and effective security rules.

**Exam skill:** Explain why ICMP and TCP can disagree, and know which tool names the blocking rule.

1. **Break it on purpose**: Set `nsg_allows_app_port = false` and apply. Only NSG rule 100 changes, from Allow to Deny.

   ```bash
   terraform plan -out=bf1.tfplan
   terraform apply bf1.tfplan
   ```

   Expect: 1 object changed: the NSG. Nothing is destroyed.

2. **See the symptom**

   ```bash
   ./scripts/netwatch-check.sh app
   ```

   Expect: The curl prints 000 (no connection) while the ping still shows replies.

3. **Ask IP flow verify**

   ```bash
   ./scripts/netwatch-check.sh ipflow
   ```

   Expect: Access Denied, rule app-port for the client packet. The second call is still Denied by DenyAllInBound.

4. **Confirm with the effective rules**

   ```bash
   ./scripts/netwatch-check.sh rules
   ```

   Expect: Rule app-port now shows Deny at priority 100, ahead of AllowVnetInBound at 65000.

5. **Fix it and re-run the same tool**: Set `nsg_allows_app_port = true`, apply, then run the helper again.

   ```bash
   terraform apply
   ./scripts/netwatch-check.sh ipflow
   ```

   Expect: Access Allowed again, and `app` prints 200.

6. **Checkpoint**: Why did ping still work while the port was denied? Answer: ping is ICMP, which does not match rule 100 (TCP 8080) and so reaches the default allow rule at 65000. IP flow verify tests TCP and UDP only, so it cannot test the ping itself.

## Activity 4: Flow logs, Traffic Analytics and the KQL cookbook

**Goal.** Open gates 2 and 3, generate traffic, read the raw flow log in storage and the enriched rows in the workspace, and run the cookbook queries.

**Exam skill:** Read a flow tuple, know where the raw and enriched data live, and explain the delay before data appears.

1. **Open gates 2 and 3**: Set `deploy_monitoring = true` and `deploy_flow_logs = true`. Keep `traffic_analytics_enabled = true`.

   ```bash
   terraform plan -out=logs.tfplan
   terraform apply logs.tfplan
   ```

   Expect: A workspace, a storage account, a random suffix and two VNet flow logs (client and server). (Designed, not tested; check the provider docs for the flow log arguments.) Billing starts for logs.

2. **Confirm the flow logs**

   ```bash
   ./scripts/netwatch-check.sh flowlogs
   ```

   Expect: Two flow logs, enabled, for the client and server VNets.

3. **Generate traffic**: Run it a few times, a minute apart.

   ```bash
   ./scripts/netwatch-check.sh app
   ```

   Expect: 200 each time.

4. **Look for the raw blobs**: After about 5 to 10 minutes, a JSON blob appears in the storage account's flow log container. Open one and find the tuple for port 8080.

   ```bash
   az storage blob list --account-name <storage_account output> -c insights-logs-flowlogflowevent --auth-mode login -o table
   ```

   Expect: Blobs named by date and hour. The container name may differ by version: check the portal. A tuple like 1730000000000,10.80.0.10,10.81.0.10,50300,8080,6,O,B,... with the state B or C.

5. **Query the enriched rows**: Set `WORKSPACE_ID` to the `workspace_id` output. Wait 10 to 30 minutes after the traffic.

   ```bash
   WORKSPACE_ID=<workspace_id output> ./scripts/netwatch-check.sh query
   ```

   Expect: Rows with FlowType IntraVNet or InterVNet, FlowStatus A and DestPort 8080. Run `NTANetAnalytics | getschema` in the workspace and adjust column names if they differ.

6. **Run cookbook queries 1 to 4**: Open `queries/netwatch-queries.kql` in the workspace Logs blade.

   Expect: Query 1 shows a recent timestamp. Query 4 should be empty while the page works.

7. **Checkpoint**: The flow log is written about every minute and Traffic Analytics runs every 10 minutes. Why can a query for 'now' return nothing? Answer: the enriched rows arrive 10 to 30 minutes later, so look back further and widen the time range.

## Activity 5: Connection Monitor, packet capture and false alarms

**Goal.** Open gate 4 to run a continuous TCP probe, read its results, capture packets on the server, then provoke a false alarm with an unrealistic threshold.

**Exam skill:** Design a probe on the real port, read pass and fail with thresholds, and use packet capture as the last, narrow tool.

1. **Open gate 4**: Set `deploy_connection_monitor = true`.

   ```bash
   terraform plan -out=cm.tfplan
   terraform apply cm.tfplan
   ```

   Expect: 1 object: the Connection Monitor with one test group. It needs the agent extension from gate 1 and the workspace from gate 2. (Designed, not tested.)

2. **Read the results**: After a few minutes open the monitor in the portal, or query the workspace.

   ```bash
   az monitor log-analytics query -w <workspace_id output> --analytics-query "NWConnectionMonitorTestResult | where TimeGenerated > ago(30m) | summarize checks = sum(ChecksTotal), failed = sum(ChecksFailed) by TestConfigurationName" -o table
   ```

   Expect: Checks growing every 30 seconds and failed equal to 0.

3. **Capture packets on the server**: Set `STORAGE_ACCOUNT` to the output name. The capture runs for 60 seconds and keeps only TCP port 8080.

   ```bash
   STORAGE_ACCOUNT=<storage_account output> ./scripts/netwatch-check.sh capture
   ```

   Expect: A packet capture named cap-lab. In the next minute run `./scripts/netwatch-check.sh app`, then open the .cap file in a packet viewer: SYN, SYN-ACK, ACK and the HTTP request.

4. **Provoke a false alarm**: Set `monitor_rtt_threshold_ms = 1` and apply. Both VMs are in one region, so the round trip is typically more than 1 ms.

   ```bash
   terraform apply
   ```

   Expect: The test result turns to Fail with the RTT criterion even though `app` still prints 200.

5. **Restore a sensible threshold**: Set the threshold back to 100 (or to a measured baseline plus margin) and apply.

   ```bash
   terraform apply
   ```

   Expect: Checks pass again.

6. **Checkpoint**: The page works but the monitor alerts. Which side is wrong? Answer: the test configuration. A monitor measures against the threshold you set, so an unrealistic RTT or an ICMP probe against a host that filters ICMP produces permanent false alarms.

## Activity 6: Azure Firewall, asymmetric routing and the structured logs

**Goal.** Open gate 5, confirm the healthy path through the firewall, break it with an asymmetric return, and diagnose it from routes, firewall logs and flow logs.

**Exam skill:** Correlate the firewall rule hit, the NSG decision and the flow counters, and recognise asymmetric routing by comparing next hops in both directions.

1. **Open gate 5 (expensive)**: Set `deploy_firewall = true`. Azure Firewall Standard bills by the hour and a public IP is created. Plan to destroy it in the same session.

   ```bash
   terraform plan -out=fw.tfplan
   terraform apply fw.tfplan
   ```

   Expect: About 18 objects: the hub VNet and subnet, four peerings, a public IP, a policy and rule collection group, the firewall, a diagnostic setting, two route tables and two associations. The firewall can take several minutes. (Designed, not tested.)

2. **Confirm the healthy path**

   ```bash
   ./scripts/netwatch-check.sh nexthop
   ./scripts/netwatch-check.sh app
   ```

   Expect: Next hop type VirtualAppliance, IP 10.82.0.4. The curl prints 200.

3. **Read the firewall log**: Wait a few minutes for the structured table.

   ```bash
   AZFWNetworkRule | where TimeGenerated > ago(30m) | project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action, Rule
   ```

   Expect: Rows with Action Allow, Rule allow-app-port. Run it in the workspace Logs blade.

4. **Break it: asymmetric return**: Set `symmetric_return = false` and apply. The server subnet loses its route table.

   ```bash
   terraform apply
   ```

   Expect: 1 route table and its association are destroyed.

5. **See the symptom and gather the evidence**

   ```bash
   ./scripts/netwatch-check.sh app
   ./scripts/netwatch-check.sh routes
   ```

   Expect: The curl prints 000. The client's route to 10.81.0.0/24 goes to 10.82.0.4. The server's route to 10.80.0.0/24 is the peering: different next hops for the two directions.

6. **Read the other logs**: Run query 6 and query 7 from the cookbook, then query 4.

   Expect: Firewall Allow rows still appear. Flow trace shows SYN and ACK packets without a SYN-ACK for the pair. Query 4 lists the pair with return bytes of zero at the client.

7. **Fix it and destroy the firewall**: Set `symmetric_return = true`, apply and test. When you are done, set `deploy_firewall = false` and apply.

   ```bash
   terraform apply
   ./scripts/netwatch-check.sh app
   ```

   Expect: The curl prints 200 again.

8. **Checkpoint**: The firewall logged Allow, the NSG logged Allow and the page hung. What did the firewall never see? Answer: the SYN-ACK. The server replied directly over the peering, so the stateful firewall had no complete session and dropped the client's ACK.

## Activity 7: No data in Traffic Analytics, then clean up

**Goal.** Switch Traffic Analytics off to reproduce an empty table, find the cause, restore it, and destroy the lab.

**Exam skill:** Diagnose a missing-data problem from the flow log settings inward, and clean up in reverse order of cost.

1. **Break it: storage only**: Set `traffic_analytics_enabled = false` and apply. The flow logs keep writing JSON to storage.

   ```bash
   terraform apply
   ```

   Expect: 2 flow logs updated in place. (Provider behaviour for an updated block: check the plan.)

2. **Generate traffic and wait**: Run the app check a few times and wait 30 minutes.

   ```bash
   ./scripts/netwatch-check.sh app
   ```

   Expect: 200 each time.

3. **See the symptom**: Run cookbook query 1 for a window that starts after the change.

   ```bash
   NTANetAnalytics | where TimeGenerated > ago(30m) | summarize count()
   ```

   Expect: Zero records for the new window, while the raw blobs in storage keep growing.

4. **Find the cause**: Read the flow log settings.

   ```bash
   ./scripts/netwatch-check.sh flowlogs
   az network watcher flow-log show --location westeurope --name nw28-fl-client
   ```

   Expect: The output has no Traffic Analytics workspace or the flag is disabled. That is the cause.

5. **Fix it and re-test**: Set `traffic_analytics_enabled = true`, apply, generate traffic and wait.

   ```bash
   terraform apply
   ```

   Expect: New rows appear in NTANetAnalytics after the next interval.

6. **Destroy in reverse order**: Set the gates back to false in this order: firewall, Connection Monitor, flow logs, VMs, monitoring. Or destroy everything.

   ```bash
   terraform apply
   terraform destroy
   ```

   Expect: Gates back to false destroy their stage. The workspace and storage account go last. Check the portal for a resource group named NetworkWatcherRG: it is not part of the lab and stays.

7. **Checkpoint**: Traffic flows and the flow log exists, yet Traffic Analytics is empty. Name three places to look. Answer: the flow log's Traffic Analytics setting and workspace, the time range against the processing interval, and the workspace region and resource provider registration.
