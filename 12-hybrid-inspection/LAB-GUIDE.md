# Lab guide: hybrid inspection of branch traffic through a hub Azure Firewall

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. The lab ships no apply and no destroy command. Gateways, the firewall and Bastion bill while they exist. Commands marked *(added in this edition)* are not in the original README or guide.

## Activity 1: Prerequisites, local checks and plan review

**Goal.** Run every check that needs no deployment, then preview the closed substrate.

**Exam skill.** Know what must be checked before anything is billed, and what a mocked or local check does not prove.

1. **Local checks (no Azure)**: From the `lab/` folder.

   ```bash
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Source checks pass; the 17 mocked plan cases run. `init` may download the provider. None of this proves Azure behaviour.

2. **Review a private plan**: Fill only non-secret fields in a private copy of `terraform.tfvars.example`. First plan the closed substrate: `deploy_lab` and `image_prerequisites_confirmed` true, every other gate false.

   ```bash
   set -euo pipefail
   umask 077
   : "${TFVARS:?Set the private reviewed input-file path; never print its contents}"
   PLAN_DIR=$(mktemp -d "$PWD/hybrid-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$TFVARS" -out="$PLAN_DIR/review.tfplan"
   ```

   Expect: Only dedicated resources: two gateways, five public IPs, firewall, three route tables, six peerings, NSGs, Bastions, VMs, workspace. The lab ships **no apply command**: deployment is a separately approved action.

## Activity 2: Load the context, open Bastion and check readiness

**Goal.** Verify the deployed identities and reach each VM through its own Bastion.

**Exam skill.** Separate management paths from the test path, and know why local readiness is not remote proof.

1. **Load and check the context**: After the approved closed deployment. `load_context` validates the subscription, the exact firewall, policy, workspace, VM, NIC, VNet, gateway, route table and Bastion IDs, and that F lies inside 10.0.1.0/26.

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   : "${SUBSCRIPTION_ID:?Set the explicitly approved subscription UUID}"
   export SUBSCRIPTION_ID
   source ./scripts/common.sh
   load_context
   FIREWALL_ID=$(read_output firewall_id)
   POLICY_ID=$(read_output firewall_policy_id)
   F=$(read_output firewall_private_ip)
   ADMIN=$(read_output admin_username)
   ```

   Expect: No connections yet: `connection_ids` is an empty map. Primary policy and test NSGs are Deny.

2. **Bastion and local readiness**: Connect to each VM through its own Bastion (branch → `branch-bastion`, spoke → `azure-bastion`), then run the readiness check on the VM. The runbook's `case` statement sets `ROLE` (`branch` or `spoke`) and `BASTION_ROLE` (`branch` or `azure`).

   ```bash
   VM_ID=$(read_map_output vm_ids "$ROLE")
   BASTION=$(read_map_output bastion_names "$BASTION_ROLE")
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$BASTION" --target-resource-id "$VM_ID" \
     --auth-type ssh-key --username "$ADMIN" --ssh-key "$SSH_PRIVATE_KEY_FILE"
   # on the VM
   READY_RUN=$(mktemp -d "$HOME/hybrid-ready-XXXXXXXX")
   hybrid-ready > "$READY_RUN/readiness.json" 2> "$READY_RUN/readiness.stderr"
   ```

   Expect: Branch runs `azure-hybrid-fixture@8082.service`, spoke runs `@8080` and `@8081`; marker `azure-hybrid-fixture-v1`; config `/etc/azure-hybrid-lab.json`. Local readiness is not a remote result.

## Activity 3: Create the connections and verify every route

**Goal.** Bring up the tunnel pair, save the control plane and read every effective route.

**Exam skill.** Prove steering with effective routes, not with a Connected status, and know which routes the firewall needs.

1. **Create the two connections**: Only after approval of the PSK handling. In your private copy of the tfvars file set `deploy_lab`, `image_prerequisites_confirmed` and `create_connections` to true. Supply `vpn_shared_key` through your secure input workflow, for example `TF_VAR_vpn_shared_key` injected by your secret runner. Never type it into a terminal or a file. Then review the plan. The lab includes no example key, no secret retrieval and no apply command.

   ```bash
   # added in this edition: the same plan command as Activity 1, with a new file name
   : "${TFVARS:?Set the private reviewed input-file path; never print its contents}"
   : "${PLAN_DIR:?Use the plan folder from Activity 1}"
   terraform plan -input=false -var-file="$TFVARS" -out="$PLAN_DIR/connections.tfplan"
   ```

   Expect: Both `hub-to-branch` and `branch-to-hub` appear, each referencing the reciprocal gateway with BGP off. After the approved apply, record both statuses through sanitised evidence. One Connected side is not enough.

2. **Collect the control plane**

   ```bash
   EVIDENCE_PARENT=$(mktemp -d "$PWD/hybrid-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/routes-closed"
   ```

   Expect: Per-command JSON, stderr and exit codes plus `timing.txt`. `connections-SKIPPED.txt` explains the skipped connection reads. Exit 0 means *reads completed*; any failed read exits 3.

3. **Verify every route**: Check A's 10.20.0.0/16 gateway route, B's 172.16.0.0/16 → F with propagation off, the exact GatewaySubnet route with propagation on, the associations and the transit flags.

   ```bash
   for ROLE in branch spoke; do
     az network nic show-effective-route-table --subscription "$SUBSCRIPTION_ID" \
       --resource-group "$RG" --name "$ROLE-nic" -o json
   done
   for ROLE in gateway branch spoke; do
     az network route-table show --subscription "$SUBSCRIPTION_ID" \
       --ids "$(read_map_output route_table_ids "$ROLE")" -o json
   done
   for ROLE in branch hub; do
     az network vnet-gateway list-learned-routes --subscription "$SUBSCRIPTION_ID" \
       --ids "$(read_map_output gateway_ids "$ROLE")" -o json
   done
   ```

   Expect: Routes as in the routing section. Record an empty or unsupported learned-routes result honestly: there is no BGP neighbour table on this non-BGP pair. Then attest `connections_ready`, `private_routes_verified` and `fixtures_ready`.

## Activity 4: Open the NSG envelope: the named Deny, then the Allow

**Goal.** See a rule name in a Deny before you allow anything, then allow only the primary flow.

**Exam skill.** Attribute a result to one control: the firewall, not an NSG, must explain the Deny.

1. **Open the NSG envelope, prove the named Deny**: Enable only `test_paths_enabled`; keep `allow_test_flow = false`. On A:

   ```bash
   BRANCH_EVIDENCE=$(mktemp -d "$HOME/hybrid-cases-XXXXXXXX")
   hybrid-probe closed --out "$BRANCH_EVIDENCE/closed-before-allow"
   ```

   Expect: Connection fails; an `AZFWNetworkRule` row for the attempted A:a → B:8080 shows Deny by `hybrid-rules` / `test-flow` / `branch-to-spoke-8080`.

2. **Allow the primary flow**: Enable only `allow_test_flow`, wait for convergence, take a new snapshot, then one fresh probe on A.

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/primary-allow"
   hybrid-probe positive --out "$BRANCH_EVIDENCE/positive"
   ```

   Expect: Correct fixture body and case; B peer = 172.16.10.10:a, local 10.20.1.20:8080; named Allow row; return route verified. HTTP 200 alone is not the result.

## Activity 5: Two named negatives, the bounded stream and restoring Deny

**Goal.** Prove that other ports and new reverse connections are denied, and that closing the rule works.

**Exam skill.** Tell a reply from a new reverse connection, and record old-flow and new-flow behaviour separately.

1. **Two named negatives**: Alternate on A; reverse-new on B (a new connection, not a reply).

   ```bash
   # A
   hybrid-probe alternate --out "$BRANCH_EVIDENCE/alternate-8081"
   # B
   SPOKE_EVIDENCE=$(mktemp -d "$HOME/hybrid-reverse-XXXXXXXX")
   hybrid-probe reverse --out "$SPOKE_EVIDENCE/reverse-new-8082"
   ```

   Expect: `deny-healthy-alternate` / `deny-branch-alt-8081` for A → B:8081; `deny-reverse-new` / `deny-spoke-new-8082` for B:b → A:8082.

2. **Bounded stream, then restore Deny**: The stream uses one socket for 5–180 s and never reconnects. After it ends, set `allow_test_flow = false` and probe again with a fresh port.

   ```bash
   hybrid-probe stream --duration 60 --out "$BRANCH_EVIDENCE/stream-allow"
   # after restoring allow_test_flow=false
   hybrid-probe closed --out "$BRANCH_EVIDENCE/closed-after-restore"
   ```

   Expect: Ordered frames and completion for the stream; a new named Deny for the fresh attempt. Old-flow and new-flow behaviour are recorded separately.

3. **Preserve the evidence window**

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/closed-restored"
   ```

   Expect: Then read the fixture journal for the exact UTC window on each VM and run the KQL in the next section.

## Activity 6: Query the logs for each case

**Goal.** Turn the evidence into a verdict with the firewall, gateway and fixture records.

**Exam skill.** Correlate the exact tuple and time with a named rule; know that missing rows are inconclusive.

1. **Prepare the firewall query**: Copy `queries/network-rule.kql` to a private file and replace its placeholders from the real case: the two `datetime(...)` values (a narrow UTC window around the attempt), the subscription UUID inside `firewall_id`, and `client_port` with the attempted source port from the probe's `connection.json`. For the alternate case use destination port 8081 and the new A port. For the reverse case use B as the source, A as the destination, port 8082 and port `b`.

   ```bash
   mkdir -p evidence
   cp queries/network-rule.kql evidence/network-rule.private.kql
   # edit evidence/network-rule.private.kql: UTC window, subscription UUID, client_port
   ```

   Expect: A private query file that names exactly one tuple and one time window.

2. **Run it**: Run the query in the Logs blade of `hybrid-logs`, or with the Azure CLI. The CLI form is *(added in this edition)* and needs the log-analytics extension.

   ```bash
   WORKSPACE=$(read_output workspace_customer_id)
   az monitor log-analytics query --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/network-rule.private.kql)" -o json
   ```

   Expect: Rows for the attempted tuple, with `Action`, `RuleCollection` and `Rule`. Denied cases name the rule (for example `deny-branch-alt-8081`). Ingestion is asynchronous: zero rows means look again, not denied.

3. **Read the gateway events**: Use `queries/gateway-events.kql` after replacing the UTC window and the subscription UUID. Gateway logs use the legacy `AzureDiagnostics` schema, and empty fields are not a healthy tunnel.

   Expect: Tunnel and route diagnostic rows around the case time, or an honest empty result.

4. **Read the fixture journal**: On the VM that hosted the listener, for the exact UTC window (on A use `azure-hybrid-fixture@8082.service`).

   ```bash
   sudo journalctl --utc --no-pager -o cat \
     -u azure-hybrid-fixture@8080.service -u azure-hybrid-fixture@8081.service \
     --since "$START_UTC" --until "$END_UTC"
   ```

   Expect: For the allowed case: the case ID and peer `172.16.10.10:a`. A denied SYN leaves no row.

5. **Record the verdicts**: Mark each case PASS, FAIL, BLOCKED or INCONCLUSIVE in `RESULTS.template.md`, with the evidence that supports it. Every runtime entry starts as NOT RUN.

   Expect: A results file in which every case has its tuple, its named rule row and its endpoint identity.

## Activity 7: Isolate, remove the connections and destroy

**Goal.** Close every path before removing the steering, then remove the lab and prove it is gone.

**Exam skill.** Know why isolation comes before route removal, and that stopping a VM does not stop gateway or firewall billing.

1. **Stop clients and restore the named Deny**: Let streams finish or stop them. Set `allow_test_flow = false` and prove a fresh attempt is denied by name, while the tunnel and the steering stay intact.

2. **Stop the listeners**: On B (on A, the same for `azure-hybrid-fixture@8082.service` and port 8082). A failed status or socket query aborts; it never counts as inactive.

   ```bash
   sudo systemctl stop azure-hybrid-fixture@8080.service azure-hybrid-fixture@8081.service
   for unit in azure-hybrid-fixture@8080.service azure-hybrid-fixture@8081.service; do
     state=$(systemctl show "$unit" --property=ActiveState --value) || exit 1
     [[ "$state" == inactive ]] || { printf 'Listener unit is not inactive.\n' >&2; exit 1; }
   done
   listeners=$(sudo ss -H -ltn 'sport = :8080 or sport = :8081') || exit 1
   [[ -z "$listeners" ]] || { printf 'A test listener still exists.\n' >&2; exit 1; }
   ```

   Expect: Units inactive, no listening sockets.

3. **Close the NSG envelope**: Set `test_paths_enabled = false` and verify both effective NSG directions and that old sessions ended. Keep steering, connections and both Bastions.

4. **Remove the connections (separate stage)**: Keep `deploy_lab` and `image_prerequisites_confirmed` true so the substrate remains. Withdraw the secure PSK input so it is really null.

   ```bash
   allow_test_flow = false
   test_paths_enabled = false
   fixtures_ready = false
   private_routes_verified = false
   connections_ready = false
   create_connections = false
   vpn_shared_key = null
   ```

   Expect: The plan deletes exactly the two connections. A stale `connections_ready = true` correctly rejects the plan.

5. **Destroy the rest with approval**: Review a full destroy plan through your approved workflow (the lab ships no destroy command): gateways and public IPs, firewall, VMs and disks, three route tables, six peerings, workspace, and finally both Bastions. Do not delete the gallery image or SSH keys.

   Expect: Only lab resources removed; check for leftover disks and public IPs. Old plans, state and backups still contain the PSK: dispose of them under your secret policy.
