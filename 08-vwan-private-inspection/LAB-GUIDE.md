# Lab guide: Virtual WAN secured hub with routing intent

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. The hub, Azure Firewall and two Bastions bill while they exist.

## Activity 1: Prerequisites and local checks

**Goal.** Confirm the right subscription and tools and run every check that needs no deployment.

**Exam skill.** Know what must exist before a deployment: the image, the key, the extensions and a configuration that validates offline.

1. **Prepare inputs and run local checks**: From `lab/`, copy the example, edit the subscription UUID, region and image version, keep all gates false and supply only the public key.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   : "${PUBLIC_KEY_FILE:?Set existing approved PUBLIC key file}"
   export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass. The tests are mock-provider plans: they say nothing about Azure. `init` may download the provider.

2. **Confirm identity and tools**: The original runbook validates every output ID against the approved subscription, the names `secured-hub` / `hub-firewall` and the fixed IPs before reading anything. Then check the CLI extensions (nothing is installed).

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   az account show --subscription "$SUBSCRIPTION_ID" \
     --query '{id:id,tenant:tenantId,name:name}' -o json
   az extension show --name virtual-wan --query version -o tsv
   az extension show --name azure-firewall --query version -o tsv
   az extension show --name bastion --query version -o tsv
   ```

   Expect: The approved tenant and subscription; extension versions recorded.

## Activity 2: Plan, review and apply

**Goal.** Preview what Terraform will create, check it against the design, and (only when approved) build it.

**Exam skill.** Read a plan for the design's key facts: AZFW_Hub with no subnet, one routing intent, no firewall UDR, no VM public IPs.

1. **Review a plan for one stage**: Check rule actions, replacements and deletions, and any drift in intent-managed connection fields. Make sure the file does not accidentally set `deploy_lab = false` on a live stack. Deploy with `deploy_lab = true`, `image_prerequisites_confirmed = true`, other gates false.

   ```bash
   set -euo pipefail
   umask 077
   : "${APPROVED_INPUTS:?Set the reviewed private input-file path for this stage}"
   PLAN_DIR=$(mktemp -d "$PWD/vwan-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/review.tfplan"
   terraform show -no-color "$PLAN_DIR/review.tfplan" > "$PLAN_DIR/review.txt"
   ```

   Expect: A plan that changes only what this stage intends. Applying it is a separate approval.

2. **Apply the reviewed plan (separate approval)**: Applying creates billed resources: the firewall, the hub, two Bastions and two VMs. Deploy only the stage you reviewed, and wait for the real convergence of the connections and the routing intent, not just a CLI success message.

   ```bash
   terraform apply "$PLAN_DIR/review.tfplan"
   terraform output
   ```

   Expect: Outputs including `firewall_private_ip`, `firewall_id`, `workspace_customer_id` and `deployment_enabled = true`. The firewall private IP is an Azure-allocated value: read it, never assume it.

## Activity 3: Record the control-plane evidence and route views

**Goal.** Save what Azure says is configured, including effective routes and effective NSGs, and capture the firewall's onward routes.

**Exam skill.** Prove steering with effective routes and the three route views, not with the existence of a route table.

1. **Collect the closed-state snapshot and route views**: The collector saves JSON, stderr and exit code for: WAN, hub, firewall, policy, intent, rules, both connections, both NICs with **effective routes** and **effective NSGs**, workload route tables and subnets, peerings, hub route tables, `defaultRouteTable` effective routes and diagnostics. It writes `firewall-onward-routes-REQUIRED.txt`: the firewall's onward routes must be captured manually from the portal (`secured-hub` > Effective Routes > Azure Firewall).

   ```bash
   EVIDENCE_PARENT=$(mktemp -d "$PWD/vwan-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/nsg-closed-baseline"
   ```

   Expect: `summary.txt` with `route_verification=NOT_PERFORMED` (by design). Intent has exactly one `PrivateTraffic` policy to the firewall ID; connections associate `defaultRouteTable` / propagate `noneRouteTable`; no direct peering; both NICs route 10/8 to F.

2. **Optional: Network Watcher next hop**

   ```bash
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vm "$APP_VM_ID" --nic app-nic \
     --source-ip 10.10.1.10 --dest-ip 10.20.1.20 -o json
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vm "$BACKEND_VM_ID" --nic backend-nic \
     --source-ip 10.20.1.20 --dest-ip 10.10.1.10 -o json
   ```

   Expect: Next hop type `VirtualNetworkGateway` with F's IP in both directions. This is a route lookup, not proof of delivery. Only use an existing Network Watcher.

## Activity 4: Prove each endpoint locally through its own Bastion

**Goal.** Reach each private VM through the Bastion in its own VNet and confirm the fixtures are healthy.

**Exam skill.** Separate local health from the cross-spoke path: a healthy listener makes a later negative result credible.

1. **Prove each endpoint locally through its own Bastion**

   ```bash
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name backend-bastion \
     --target-resource-id "$BACKEND_VM_ID" --auth-type ssh-key \
     --username "$ADMIN" --ssh-key "$SSH_PRIVATE_KEY_PATH"
   # on B
   vwan-ready
   sudo systemctl status --no-pager azure-vwan-fixture@8080.service \
     azure-vwan-fixture@8081.service
   # on A (via app-bastion)
   vwan-ready
   sudo systemctl status --no-pager azure-vwan-fixture@8082.service
   ```

   Expect: `LOCAL_FIXTURES_READY` and the marker `azure-vwan-origin-v1`. This proves local health only, not a cross-spoke path.

## Activity 5: Firewall-deny baseline, then the positive test

**Goal.** Open the NSG envelopes, observe the named firewall Deny, then open the single Allow and run the positive and alternate tests.

**Exam skill.** Know why the NSG envelope is opened before the negative tests and what each result proves.

1. **Open the NSG envelopes and run the firewall-deny baseline**: Apply the reviewed stage `fixtures_ready`, `private_routes_verified`, `test_paths_enabled` = true, `allow_test_flow` = false. Snapshot again, then on A:

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/firewall-closed-baseline"
   # on A
   APP_EVIDENCE=$(mktemp -d "$HOME/vwan-app-XXXXXXXX")
   vwan-probe closed --out "$APP_EVIDENCE/firewall-closed-8080"
   ```

   Expect: No backend response; an `AZFWNetworkRule` row `private-rules` / `test-flow` / `app-to-backend-8080`, Action **Deny**, for the attempted tuple.

2. **Open the single firewall Allow and run the positive**: Apply only `allow_test_flow = true`; check the plan changes just that rule action. Snapshot `allow-8080`, then on A:

   ```bash
   vwan-probe positive --out "$APP_EVIDENCE/positive-8080"
   vwan-probe alternate --out "$APP_EVIDENCE/alternate-8081"
   ```

   Expect: Positive: fixture identity, peer = 10.10.1.10 **and** the recorded port a, named Allow. Alternate: B:8081 healthy locally, `deny-app-alt-8081` Deny for tuple A:a2 → B:8081.

## Activity 6: Reverse-new and stream tests

**Goal.** See a new reverse connection denied and watch an open session end when the rule flips.

**Exam skill.** Tell a reply from a new connection, and know that a firewall Allow-to-Deny change affects existing sessions.

1. **Run the reverse-new test on B**

   ```bash
   BACKEND_EVIDENCE=$(mktemp -d "$HOME/vwan-backend-XXXXXXXX")
   vwan-probe reverse --out "$BACKEND_EVIDENCE/reverse-new-8082"
   ```

   Expect: `deny-reverse-new` / `deny-backend-new-8082` Deny for B's actual port b.

2. **Hold a stream open while closing the firewall gate**: Wait for the first frame, then apply `allow_test_flow = false`, recording start, completion and observed effect. Snapshot `firewall-closed-after-allow`.

   ```bash
   vwan-probe stream --duration 180 --out "$APP_EVIDENCE/stream-firewall-close"
   # after the reviewed change allow_test_flow=false takes effect:
   vwan-probe closed --out "$APP_EVIDENCE/closed-after-allow"
   ```

   Expect: The stream is dropped after the Deny takes effect (documented firewall behaviour). If the update takes longer than the 180 s stream, that part is **inconclusive**. The fresh `closed` attempt shows the named Deny.

## Activity 7: Query the firewall logs

**Goal.** Turn the evidence into a verdict by joining the probe files, the fixture journal and the firewall row.

**Exam skill.** Correlate time, source port and rule name to prove a decision; know that no source proves routing, permission and delivery on its own.

1. **Fill the query from the probe's evidence**: Copy `queries/network-rule.kql`, then replace every placeholder: the UTC window around the case, the firewall resource ID, A's recorded source port from `result.json` (`attempted_local[1]`) and the destination port.

   ```bash
   grep -A3 -E 'attempted_local|started_utc|completed_utc' "$APP_EVIDENCE/positive-8080/result.json"
   cp queries/network-rule.kql "$EVIDENCE_PARENT/network-rule.kql"
   ```

   Expect: The recorded source port and the start and end times. Never assume the port.

2. **Run the saved query**: `--workspace` takes the workspace **customer ID** (output `workspace_customer_id`), not the ARM resource ID `workspace_id`, and never a shared key.

   ```bash
   : "${QUERY_FILE:?Set the reviewed KQL file with actual tuple/resource/UTC values}"
   QUERY_DIR=$(mktemp -d "$EVIDENCE_PARENT/log-query-XXXXXXXX")
   cp -- "$QUERY_FILE" "$QUERY_DIR/query.kql"
   az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" \
     --workspace "$WORKSPACE_CUSTOMER_ID" \
     --analytics-query "$(cat "$QUERY_DIR/query.kql")" -o json \
     > "$QUERY_DIR/result.json"
   ```

   Expect: JSON rows with `Action`, `Policy`, `RuleCollectionGroup`, `RuleCollection` and `Rule`. Log ingestion is asynchronous: re-query within a bounded window. An empty result is inconclusive, not a Deny.

3. **Read the fixture journal for the same window**: Compare the delivered request with the firewall row.

   ```bash
   sudo journalctl --utc --since "$START_UTC" --until "$END_UTC" \
     -u azure-vwan-fixture@8080.service -u azure-vwan-fixture@8081.service \
     --no-pager -o cat
   ```

   Expect: A delivered request matches case, peer IP and port, local port, path and UTC. A denied SYN leaves no journal entry, which is expected.

## Activity 8: Isolate the workloads, then destroy

**Goal.** Close every gate and stop the listeners before anything is removed, then review a destroy plan.

**Exam skill.** Know that removing routing intent is a routing change and that Terraform may remove the intent before the connections.

1. **Stop the fixtures on B (and 8082 on A)**

   ```bash
   sudo systemctl stop azure-vwan-fixture@8080.service azure-vwan-fixture@8081.service
   sudo systemctl show azure-vwan-fixture@8080.service --property=ActiveState --value
   ss -H -ltn '( sport = :8080 or sport = :8081 )'
   ```

   Expect: `inactive` and no listening socket. On A, do the same for `azure-vwan-fixture@8082.service` and port 8082. Any other result stops the teardown.

2. **Firewall Deny, then NSG envelopes closed**: Confirm `allow_test_flow = false` is effective, then apply `test_paths_enabled = false` with `deploy_lab` still true. Verify both NICs show rules 100 and 101 as Deny.

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/pre-teardown-isolated"
   ```

   Expect: Effective NSGs Deny on the right NIC and direction; Bastion management still works.

3. **Review the destroy plan**: Review a complete destroy plan, not targeted deletions, and authorise it separately. The lab contains no apply or destroy command of its own.

   ```bash
   terraform plan -destroy -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/destroy.tfplan"
   terraform show -no-color "$PLAN_DIR/destroy.tfplan" > "$PLAN_DIR/destroy.txt"
   ```

   Expect: Only the dedicated lab resources are listed. Keep the gallery image and the SSH key. Deleting state does not delete resources.

4. **Apply the destroy and verify**: After approval, apply the saved destroy plan. Then check for leftovers: Bastions and public IPs, the firewall and policy, the hub, the WAN and the connections, VMs and disks, and the workspace.

   ```bash
   terraform apply "$PLAN_DIR/destroy.tfplan"
   terraform state list
   az group exists --name inspection-vwan
   ```

   Expect: An empty state list and `false`. The resource group deletion guard refuses to delete a group that still holds resources Terraform did not create: never switch it off.
