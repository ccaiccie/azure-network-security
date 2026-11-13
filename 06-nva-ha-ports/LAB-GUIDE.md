# Lab guide: two Linux NVAs behind an HA-ports internal load balancer

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Four VMs, a Standard load balancer and Bastion bill while they exist.

## Activity 1: Local checks and inputs

**Goal.** Prepare the inputs and run every check that needs no Azure deployment.

**Exam skill.** Know what must exist before a deployment: an approved image, a subscription, a plan that is checked offline and a gate that defaults to off.

1. **Local checks and inputs (lab folder)**: Offline only: no provider download, no Azure calls, no nft or sysctl.

   ```bash
   bash scripts/check-local.sh
   umask 077
   cp terraform.tfvars.example terraform.tfvars
   # Edit subscription, location, image version ID; keep deploy_lab=false
   ```

   Expect: Syntax checks, 135 source-contract assertions and 56 unit tests pass; Terraform steps print NOT RUN if Terraform is absent.

2. **Terraform checks (after an approved init)**

   ```bash
   terraform fmt -check -recursive
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: 10 plan-only mocked-provider cases pass. They still need the real provider schema and create nothing.

## Activity 2: Deploy and take the control-plane snapshot

**Goal.** Build the lab after approval and save what Azure says is configured, including effective routes and NSGs.

**Exam skill.** Prove steering with effective routes and next hop, not with the route table resource, and know that the guest's `ip route get` is not Azure's view.

1. **Deploy (separately approved)**: Set `deploy_lab = true` and `image_prerequisites_confirmed = true`, review the complete real plan (four VMs, ILB, Bastion, four peerings, three route tables, NSGs) and its cost, then apply through your approved workflow. First boot leaves both NVAs **closed and withdrawn**.

   Expect: Outputs such as `lb_id`, `lb_frontend_ip`, `app_vm_id`, `backend_vm_id`, `nva_vm_ids`, `bastion_name`.

2. **Pin the session and take a control-plane snapshot**

   ```bash
   export SUBSCRIPTION_ID='<approved subscription UUID>'
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   source scripts/common.sh
   load_context
   RUN=$(mktemp -d "$HOME/nva-control-run.XXXXXX")
   bash scripts/collect-control-plane.sh "$RUN/baseline"
   ```

   Expect: `load_context` refuses a subscription that does not match the LB in state. The snapshot holds the LB frontend/pool/rule/probe, all four NICs (forwarding **true** only on nva1/nva2), effective routes and NSGs, route tables, peerings and DipAvailability/VipAvailability.

3. **Optional: Network Watcher next hop**: Only if a Network Watcher already exists in the region. Repeat for B → A and for each NVA's onward lookups (source 10.0.2.4 / 10.0.2.5).

   ```bash
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vm "$A_VM_ID" --nic app-nic \
     --source-ip 10.10.1.10 --dest-ip 10.20.1.20 -o json
   ```

   Expect: A and B: `VirtualAppliance` 10.0.2.10. NVAs: `VNetPeering`, never back to F.

## Activity 3: Reach every VM and take the guest baseline

**Goal.** Open private sessions to all four VMs and confirm each starts closed and withdrawn.

**Exam skill.** Separate the management path from the tested path, and know that the probe port, the probe source and the NSG rule 120 must all agree.

1. **Open a Bastion tunnel and an SSH terminal per VM**: Native tunneling needs the already-installed Bastion extension (dynamic install is off). Use one foreground tunnel and one SSH terminal per VM, changing only the VM ID and the local port. The example uses A; `backend_vm_id` and the `nva_vm_ids` map give the others. Verify SSH host keys through the approved channel and never disable host-key checking.

   ```bash
   APP_ID=$(terraform output -raw app_vm_id)
   BASTION=$(terraform output -raw bastion_name)
   az network bastion tunnel --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$BASTION" --target-resource-id "$APP_ID" \
     --resource-port 22 --port 50022
   # separate local terminal (your approved private key stays local)
   ssh -p 50022 labadmin@127.0.0.1
   ```

   Expect: One terminal per VM (B, nva1 and nva2 with other VM IDs and local ports). Keep a second session to the node you will disrupt later.

2. **Guest baseline (NVAs and B)**

   ```bash
   # each NVA (read-only)
   sudo nva-control status
   ip -4 route get 10.20.1.20
   NVA_IP=10.0.2.4   # 10.0.2.5 on nva2
   curl -q --noproxy '*' --connect-timeout 3 --max-time 5 \
     --write-out '%{http_code}\n' "http://$NVA_IP:8008/healthz"
   # B
   backend-ready
   ```

   Expect: NVAs: closed, `advertised=false`, health **503**. B: `LOCAL_FIXTURES_READY:8080 and8081`. Do not continue on NOT READY.

## Activity 4: Activate one node and prove the positive and negative paths

**Goal.** Open nva1 only, then show a successful flow on 8080 and a named drop on 8081, with evidence from both ends.

**Exam skill.** Name the evidence that proves flow ownership and a correct NVA deny; a timeout alone proves nothing.

1. **Activate, then advertise one node**

   ```bash
   sudo nva-control activate --confirm-guest-change   # each NVA; stays withdrawn
   sudo nva-control status
   sudo nva-control advertise --confirm-guest-change  # nva1 only, first
   ```

   Expect: nva1 health 200 and, after convergence, the only eligible backend. Later swap: withdraw nva1, advertise nva2.

2. **Evidence on both NVAs, probes on A**

   ```bash
   # both NVAs, started first
   sudo nva-evidence --capture-seconds 90 --out "$NODE_RUN/observation"
   # A, new output paths every time
   PROBE_RUN=$(mktemp -d "$HOME/nva-probes.XXXXXXXX")
   nva-probe positive --out "$PROBE_RUN/positive"
   nva-probe negative --out "$PROBE_RUN/alternate-port"
   ```

   Expect: Positive: fixture identity matches and peer = A, both directions on the owner. Negative: SYN on the owner and `deny-alternate-8081` counter up. Exit 0 is not PASS: read `result.json`.

## Activity 5: Failure experiments: withdraw and break forwarding

**Goal.** Run two bounded experiments on the stream's owner and report the old stream and the fresh flows separately.

**Exam skill.** Tell eligibility, forwarding and session survival apart, and know that no state is replicated.

1. **Make sure the survivor is eligible and the owner is proven**: A long-lived test needs a proven single owner first, and an eligible survivor **before** you interrupt the owner. Capture both nodes, then start A's stream in its own terminal and keep its tuple.

   ```bash
   # A, foreground, its own terminal
   RUN=$(mktemp -d "$HOME/nva-stream.XXXXXX")
   nva-probe stream --duration 120 --out "$RUN/original-stream"
   ```

   Expect: The stream writes `connection.json` before it connects, then `frames.ndjson` once per second. Both-node captures show which NVA owns the tuple.

2. **Withdraw eligibility on the owner (bounded)**: On the proven owner run one bounded helper. During the 30 seconds, start fresh positive cases from another terminal on A, each with a new output directory.

   ```bash
   # proven owning NVA, one approved experiment at a time
   sudo nva-control withdraw-for --seconds 30 --confirm-guest-change
   # A, another terminal
   nva-probe positive --out "$RUN/fresh-during-withdraw"
   ```

   Expect: Health returns 503; after convergence fresh flows use the other NVA. The old stream **may continue** on its original node. The helper holds an exclusive lock and writes `events.jsonl` (start, then restored).

3. **Break forwarding on the owner (a different run)**: Re-establish a proven owner and a ready survivor first. `fail-forwarding` installs a closed owned table and withdraws health, keeping conntrack and the VM. It is not a crash, reboot or state-loss test.

   ```bash
   sudo nva-control fail-forwarding --seconds 30 --confirm-guest-change
   # A, another terminal
   nva-probe positive --out "$RUN/fresh-during-fail"
   ```

   Expect: Fresh flows succeed on the survivor after convergence. The old stream stalls, times out (5 s socket timeout) or resumes on restore. Report both separately.

4. **Metrics for the window**

   ```bash
   for NODE_IP in 10.0.2.4 10.0.2.5; do
     az monitor metrics list --subscription "$SUBSCRIPTION_ID" --resource "$LB_ID" \
       --metric DipAvailability --aggregation Average --interval PT1M \
       --start-time "$START_UTC" --end-time "$END_UTC" \
       --filter "BackendIPAddress eq '$NODE_IP'" -o json
   done
   ```

   Expect: Probe status per NVA, one-minute averages. A bin spanning the change may be fractional, late or empty.

## Activity 6: All probes down, then restore or close

**Goal.** Show that no eligible node means no new flow, then put the lab back to a known state.

**Exam skill.** Know what `AllProbedDown` does and does not do, and that closing a node never stops billing.

1. **Withdraw both nodes in overlapping windows (optional)**: This is a health test, not a drop-all switch. Withdraw each node, wait until the observed state shows both ineligible, then run one fresh positive from A. Do not guess a sleep time.

   ```bash
   # each NVA, separately authorized
   sudo nva-control withdraw --confirm-guest-change
   # A, after observed convergence
   nva-probe positive --out "$RUN/all-down"
   ```

   Expect: With `AllProbedDown`, the fresh flow is not dispatched and fails; `DipAvailability` shows both nodes ineligible. Existing flows can still work if both nodes still forward.

2. **Restore advertisement and verify**: Read status and persistent events first. Re-advertise the intended nodes, then repeat a positive, a negative and the single-node controls.

   ```bash
   sudo nva-control status
   sudo nva-control advertise --confirm-guest-change   # each node you intend to keep eligible
   nva-probe positive --out "$RUN/after-restore-positive"
   nva-probe negative --out "$RUN/after-restore-negative"
   ```

   Expect: 8080 works again and 8081 is still dropped by `deny-alternate-8081`. Keep before and after evidence separate.

3. **Recover or close**: `recover` restores the recorded mode and **may reopen** a node you closed, so approve that first. `close` blocks transit and withdraws health; `restore-original` also restores the pre-activation sysctls. Neither stops Azure billing.

   ```bash
   sudo nva-control status
   sudo nva-control recover --confirm-guest-change   # only if a recovery record is pending
   sudo nva-control close --confirm-guest-change     # final closure, each NVA
   ```

   Expect: `close` leaves a closed table with health withdrawn on each node. A reboot is not a rollback: `nva-boot` installs a closed table first.

## Activity 7: Destroy and verify

**Goal.** Remove everything the lab built and prove it is gone.

**Exam skill.** Know that failing a probe or closing an NVA is not deletion, and that deletion needs an approved destroy plan.

1. **Finish experiments and save the evidence**: Stop streams and captures, confirm every bounded helper has exited and released its lock, and export client results, both NVAs' evidence, B's journal and the control-plane snapshots to approved private storage. Note the resource group name now: after the destroy, `load_context` will refuse to run.

   Expect: A private evidence folder. Captures contain plain HTTP, so keep them private.

2. **Review a destroy plan for the dedicated state only**: Setting `deploy_lab = false` after deployment also plans deletion, but an explicit destroy plan is clearer. The resource group has a deletion guard (`prevent_deletion_if_contains_resources`); never switch it off. Never delete the external gallery image or the operator's key.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   ```

   Expect: Only the dedicated lab resources are listed: four VMs, the ILB, Bastion and its public IP, peerings, route tables, NSGs and the resource group.

3. **Apply the destroy plan (after approval)**

   ```bash
   terraform apply destroy.tfplan
   ```

   Expect: Terraform deletes the lab. Billing for the lab resources stops when they are gone.

4. **Verify removal**: Check that the resources are really gone and look for leftover disks or public IPs. Deleting the state file is not deleting resources; a partial teardown is still an open action.

   ```bash
   terraform state list
   az group exists --subscription "$SUBSCRIPTION_ID" --name "$RG"
   ```

   Expect: `terraform state list` prints nothing and `az group exists` prints `false`.
