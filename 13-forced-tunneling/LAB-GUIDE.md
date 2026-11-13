# Lab guide: Azure Firewall forced tunnelling to an upstream perimeter

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall and Bastion bill while they exist. Commands marked **Added in this edition** are not in the original README. `terraform fmt -recursive` was applied in this edition and `tests/source_contract.py` now normalises whitespace around `=` (126 assertions pass); `init`, `validate` and the mock plans were not run.

## Activity 1: Offline checks and prerequisites

**Goal.** Prepare the inputs and run every check that needs no Azure resource.

**Exam skill.** Know what must exist before any deployment: the approved image, the pinned toolchain and a mock-provider plan.

1. **Copy the example inputs and fill them in**: Copy the public example file and replace every placeholder with real, non-secret values: the subscription UUID, an available region, your existing public SSH key and the approved Compute Gallery image version ID. Leave all nine booleans false for now. Invalid placeholders deliberately block a deployment. **Added in this edition**: the original README names no such command.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

   Expect: A `terraform.tfvars` file with no secrets. Never put a private key, password or workspace key in it.

2. **Run the offline checks**: From the lab folder. The Terraform commands need the pinned toolchain and were never run by the original author. `terraform fmt -check` should now pass because this edition applied `terraform fmt`.

   ```bash
   bash scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local suite passes. The tests use a mock provider and only plan.

## Activity 2: Create the closed substrate and save the control plane

**Goal.** Preview and, only when approved, build the lab with every gate closed, then snapshot what Azure says is configured.

**Exam skill.** Read a plan for the design's key facts: a management IP configuration, no data public IP, and public IPs only on the perimeter and origin.

1. **Plan only the closed substrate**: Set only `deploy_lab` and `image_prerequisites_confirmed` to true (in `terraform.tfvars`) and keep every other gate false. Plan, save the plan and read it before anything is applied. **Added in this edition**: the original README names no such command.

   ```bash
   terraform plan -out=substrate.tfplan
   terraform show -no-color substrate.tfplan
   ```

   Expect: The plan shows `hub-firewall` with a `management_ip_configuration` and **no** data public IP, and only the perimeter and origin have public IPs. Stop here unless the plan is approved.

2. **Apply the approved plan**: Only after separate approval. Cloud-init then starts the origin fixtures and enables `forced-prepare.service`, which installs the **closed** nftables table before setting `ip_forward = 1`. Azure Firewall and Bastion bill from this point. **Added in this edition**: the original README names no such command.

   ```bash
   terraform apply substrate.tfplan
   ```

   Expect: The plan applies. The source supplies no apply command; this one is yours to approve.

3. **Load the identity guard and collect the control plane**

   ```bash
   export SUBSCRIPTION_ID="REPLACE_WITH_APPROVED_UUID"
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   source ./scripts/common.sh
   load_context
   APP_VM_ID=$(read_map_output vm_ids app)
   PERIMETER_VM_ID=$(read_map_output vm_ids perimeter)
   APP_NIC_ID=$(read_map_output nic_ids app)
   PERIMETER_NIC_ID=$(read_map_output nic_ids perimeter)
   F=$(read_output firewall_private_ip)
   P=$(read_map_output public_ips perimeter)
   D=$(read_map_output public_ips origin)
   CONTROL_OUT="$PWD/evidence/control-initial-$(date -u +%Y%m%dT%H%M%SZ)-$$"
   ./scripts/collect-control-plane.sh "$CONTROL_OUT"
   ```

   Expect: `load_context` checks the subscription, RG and every expected resource ID. The collector saves JSON, stderr and exit codes; its summary always says `route_verification=NOT_PERFORMED`, because reading resources is not proof of forwarding.

## Activity 3: Reach the machines and check readiness and routes

**Goal.** Log in through Bastion, confirm each machine is ready and the perimeter is closed, then check route selection.

**Exam skill.** Prove steering with next hop and effective routes, and know that a local readiness result proves nothing about the chain.

1. **SSH through Bastion and check local readiness**

   ```bash
   : "${EXISTING_SSH_KEY_PATH:?Set approved local private-key file path}"
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$(read_output bastion_name)" \
     --target-resource-id "$(read_map_output vm_ids app)" \
     --auth-type ssh-key --username labadmin --ssh-key "$EXISTING_SSH_KEY_PATH"
   # then, on A and on the origin, in a new private run folder:
   RUN="$HOME/forced-evidence/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
   mkdir -p -- "$(dirname -- "$RUN")"
   mkdir -m 700 "$RUN"
   forced-ready > "$RUN/local-readiness.json"
   ```

   Expect: A reports `LOCAL_CLIENT_READY`; the origin reports `LOCAL_FIXTURES_READY` with `azure-forced-fixture@8080/8081/8082.service` up and marker `azure-forced-origin-v1`. A local 200 proves nothing about D, P or the chain.

2. **Confirm the perimeter is prepared and closed**

   ```bash
   sudo forced-control status
   sudo systemctl status forced-prepare.service --no-pager
   sudo forced-evidence
   ```

   Expect: Closed mode, no pending transition, the expected interface and sysctls. If an earlier operation failed, investigate and then run `sudo forced-control reconcile --confirm-guest-change`.

3. **Check route selection**: Needs an existing Network Watcher in the region; do not create one for this.

   ```bash
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --vm "$APP_VM_ID" --nic "$APP_NIC_ID" \
     --source-ip 10.20.1.10 --dest-ip "$D" -o json
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --vm "$PERIMETER_VM_ID" --nic "$PERIMETER_NIC_ID" \
     --source-ip 10.30.1.4 --dest-ip 10.20.1.10 -o json
   ```

   Expect: A → D via VirtualAppliance F; perimeter → A via VirtualAppliance F. Also check perimeter → D (Internet) and A → 10.40.2.4 (management peering). Then record the three readiness gates true.

## Activity 4: Open the NSG envelopes and prove the Azure stage

**Goal.** Open the network security groups and show that Azure Firewall alone denies, then alone allows.

**Exam skill.** Separate the two stages with named evidence, never with a timeout.

1. **Open the NSG envelopes, keep both policies closed**: Set `origin_access_enabled = true`, then `test_paths_enabled = true` in `terraform.tfvars`, each as its own reviewed plan. Keep `allow_test_flow = false` and the guest closed. The plan and apply commands are added in this edition.

   ```bash
   terraform plan -out=gate-origin.tfplan && terraform show -no-color gate-origin.tfplan
   terraform apply gate-origin.tfplan
   # then repeat for test_paths_enabled = true
   ```

   Expect: Effective NSGs show the exact Allow rules; nothing else changed.

2. **Named Azure Deny baseline**

   ```bash
   forced-probe closed --out "$RUN/preserve-azure-closed"
   ```

   Expect: No response, **and** an `AZFWNetworkRule` Deny row for `app-to-controlled-origin` matching the attempted tuple. A timeout alone is incomplete.

3. **Azure Allow, perimeter still closed**: Set only `allow_test_flow = true` and apply it as a reviewed plan (plan, review and apply commands are added in this edition), then run the probe.

   ```bash
   forced-probe positive --out "$RUN/preserve-perimeter-closed"
   ```

   Expect: Still no response, now with an Azure Allow row **and** the perimeter's named closed drop.

## Activity 5: Open the perimeter, capture, then close

**Goal.** Open the second stage, watch the packet change on the perimeter, then close everything and review.

**Exam skill.** Read pre- and post-translation captures and connection tracking, and know that the guest allow has no expiry.

1. **Open the perimeter and capture the first positive**

   ```bash
   # perimeter:
   sudo forced-control allow-test --confirm-guest-change --acknowledge-reviewed-scope
   sudo forced-evidence --capture --seconds 15 --packets 200 --acknowledge-sensitive-capture
   # app VM, while the capture runs:
   forced-probe positive --out "$RUN/preserve-positive"
   ```

   Expect: A complete fixture with peer P; Azure Allow; capture shows A:a → D before NAT and E:e → D after. The guest Allow is persistent with no expiry.

2. **Close and review before anything else**

   ```bash
   sudo forced-control close --confirm-guest-change
   sudo forced-control status
   ```

   Expect: Closed. Also set `allow_test_flow = false` again and verify a fresh named Azure Deny, then review the whole translation chain before a separately approved reopening.

## Activity 6: Run the named negatives and read the firewall log

**Goal.** Show that 8081 stops at Azure Firewall and 8082 at the perimeter, then read the log rows.

**Exam skill.** Match a probe tuple and time to an `AZFWNetworkRule` row and a perimeter counter.

1. **Run the two named negatives (after reopening both stages)**

   ```bash
   forced-probe alternate --out "$RUN/preserve-azure-8081"
   forced-probe perimeter --out "$RUN/preserve-perimeter-8082"
   ```

   Expect: 8081: `deny-app-8081` row. 8082: Azure Allow plus `deny-perimeter-8082-forward` evidence.

2. **Read the firewall's decision for each tuple**: A denied or allowed flow shows in `AZFWNetworkRule`. Copy the original query, fill in the real UTC window and the real D, and run it. The `az monitor log-analytics query` call is added in this edition and may need the CLI's log-analytics extension: install it deliberately first, because dynamic extension install is disabled in this lab. **Added in this edition**: the original README names no such command.

   ```bash
   cp queries/network-rule.kql evidence/network-rule.kql
   # edit the time window; then replace the D placeholder:
   sed -i "s|REPLACE_WITH_ACTUAL_ORIGIN_PUBLIC_IPV4|$D|" evidence/network-rule.kql
   WORKSPACE=$(terraform output -raw workspace_customer_id)
   az monitor log-analytics query --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/network-rule.kql)" -o json > evidence/network-rule.json
   ```

   Expect: Rows for 10.20.1.10 to D: `deny-app-8081` for 8081, `app-to-controlled-origin` Allow for 8080 and 8082 (when allowed). Rows show the pre-SNAT tuple. Ingestion can lag, so an empty result is inconclusive.

3. **Record the results**: Mark each case PASSED, FAILED, INCONCLUSIVE or NOT RUN in a copy of `RESULTS.template.md`, with the three columns configured intent, observed control plane and observed packets.

   Expect: A results file where every case has the evidence that supports it.

## Activity 7: Optional experiments: forwarding loss and private SNAT

**Goal.** Watch a bounded loss of forwarding on the perimeter, then compare the second source mode.

**Exam skill.** Know what a bounded failure is not, and why S is not F.

1. **Optional: bounded forwarding loss**

   ```bash
   # app VM:
   forced-probe stream --duration 60 --out "$RUN/preserve-stream"
   # perimeter, after the first frames:
   sudo forced-control fail-forwarding --seconds 30 --confirm-guest-change
   # app VM, during and after the window:
   forced-probe positive --out "$RUN/preserve-during-failure"
   forced-probe positive --out "$RUN/preserve-after-restoration"
   ```

   Expect: Fresh attempt inside the window fails; the stream may break (do not expect continuity); a fresh attempt after confirmed restoration completes. Allowed duration is 5–120 s.

2. **Optional: private-SNAT comparison**: Close everything, then apply `source_mode = firewall_private` with `snat_comparison_acknowledged = true` and repeat steps 3–12 in a new run. Check the observed S before querying its route:

   ```bash
   : "${OBSERVED_S:?Set the actual firewall instance source observed in private-SNAT capture}"
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --vm "$PERIMETER_VM_ID" --nic "$PERIMETER_NIC_ID" \
     --source-ip 10.30.1.4 --dest-ip "$OBSERVED_S" -o json
   ```

   Expect: S lies inside 10.0.1.0/26 and is reached via hub peering, not via the 10.20.0.0/16 → F route. Never use F as a guess for S.

## Activity 8: Close everything and tear down

**Goal.** Close each control in order, verify it, and remove the lab.

**Exam skill.** Close in order and keep management until last; deleting routes first can open a bypass.

1. **Stop the test clients**: Let bounded probes and streams finish, or interrupt only the known process. Keep their final or incomplete evidence.

2. **Restore the Azure Deny**: Reviewed plan with `allow_test_flow = false`; keep routes and the `deny-app-8081` rule. Verify with a fresh named Deny if the path is still open. The plan and apply commands are added in this edition.

   ```bash
   # set allow_test_flow = false in terraform.tfvars, then:
   terraform plan -out=close-firewall.tfplan && terraform show -no-color close-firewall.tfplan
   terraform apply close-firewall.tfplan
   ```

3. **Close the perimeter**

   ```bash
   sudo forced-control close --confirm-guest-change
   sudo forced-control status
   ```

   Expect: Closed. If a previous transition is unresolved after its lock is free: `sudo forced-control reconcile --confirm-guest-change`.

4. **Stop the origin listeners and check for sockets**

   ```bash
   sudo systemctl stop azure-forced-fixture@8080.service azure-forced-fixture@8081.service azure-forced-fixture@8082.service
   for port in 8080 8081 8082; do
     state=$(systemctl show "azure-forced-fixture@$port.service" --property=ActiveState --value)
     [[ "$state" == inactive ]] || { printf 'Listener service is not inactive\n' >&2; exit 1; }
   done
   listeners=$(sudo ss -H -ltn '( sport = :8080 or sport = :8081 or sport = :8082 )')
   [[ -z "$listeners" ]] || { printf 'Owned test listener remains\n' >&2; exit 1; }
   ```

   Expect: All three inactive and no listener left.

5. **Close the NSG gates**: Reviewed plan with `origin_access_enabled = false` and `test_paths_enabled = false`; keep `deploy_lab` and `image_prerequisites_confirmed` true and clear the three readiness attestations.

6. **Optional guest restoration**

   ```bash
   sudo forced-control restore-original --confirm-guest-change --acknowledge-reviewed-scope
   sudo forced-control status
   ```

   Expect: Restores only the 14 captured sysctls and removes the owned table. Not a full guest rollback; usually unnecessary if the VM is deleted.

7. **Remove the topology and verify**: Only now review and authorise teardown. `deploy_lab = false` requests destruction; a destroy plan makes that explicit. Do not delete the pre-existing image or SSH key. **Added in this edition**: the original README names no such command.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   terraform apply destroy.tfplan
   terraform state list
   az group exists --name inspection-forced --subscription "$SUBSCRIPTION_ID"
   ```

   Expect: Only lab resources are listed in the plan. After the apply the state list is empty and the group-exists call returns `false` (use your own `resource_group_name` if you changed it). Verify that no firewall, Bastion, public IP, disk or workspace remains.
