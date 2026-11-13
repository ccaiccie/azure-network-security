# Lab guide: Azure Gateway Load Balancer with a stateless Linux bridge filter

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied, and every command is a procedure for a future, separately approved run. The lab ships no apply or destroy command: apply reviewed plans only through your approved change process. Two load balancers, three VMs, one Standard Bastion and two public IPs bill while they exist.

**Terraform formatting note.** The Terraform in this folder was formatted with `terraform fmt`, which realigns equals signs. The lab's own `tests/source_contract.py` (run by `scripts/check-local.sh`) matches some Terraform lines by exact spacing, so after formatting it stops at its first such check (for example `main.tf missing count = var.deploy_lab ? 1 : 0`). The 85 Python unit tests still pass when run directly. Run the source check on an unformatted copy of the original package, or relax those matches; Terraform behaviour is unchanged.

## Activity 1: Prerequisites, local checks, plan and review

**Goal.** Run every check that needs no deployment, then preview what Terraform will create.

**Exam skill.** Know what must exist before a deployment, and read a plan for the design's key facts: chain off, no VM public IP, test NSG rule Deny.

1. **Prepare inputs and run local checks**: In `lab/`, copy the example and replace every placeholder. Keep all six gates false.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test
   ```

   Expect: Local syntax, source and unit checks pass. The Terraform tests are plan-only mocks; `init` may download the provider. None of this touches Azure. This course's formatted copy fails the spacing checks of `tests/source_contract.py`; see the lab notes in Running the lab. The unit tests run separately with `python3 -m unittest discover -s tests -p 'test_*.py'`.

2. **Save and review a plan**: With `deploy_lab` and `image_prerequisites_confirmed` true. Check creations and replacements, the exact client IP, image version, both load-balancer rules, chain state (off), NSGs and peerings.

   ```bash
   set -euo pipefail
   umask 077
   : "${TFVARS:?Set the private reviewed input-file path}"
   PLAN_DIR=$(mktemp -d "$PWD/gwlb-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$TFVARS" -out="$PLAN_DIR/review.tfplan"
   terraform show -no-color "$PLAN_DIR/review.tfplan" > "$PLAN_DIR/review.txt"
   ```

   Expect: A plan that creates only lab resources, chain off, `test-client-ingress` = Deny. Apply it only through your approved change process.

## Activity 2: Reach the VMs and prepare both NVAs

**Goal.** Reach the private machines through Bastion, prepare both appliances in closed mode and check the application.

**Exam skill.** Separate the management path from the data path, and know that prepare, advertise and allow are three different decisions.

1. **Guard the context, then reach a VM through Bastion**: After the initial deployment, the helper library checks every declared resource ID against the expected names before any Azure read.

   ```bash
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   source ./scripts/common.sh
   load_context
   require_extensions bastion
   : "${SSH_PRIVATE_KEY_FILE:?Set existing approved local SSH private key path}"
   az_read network bastion ssh -g "$RG" -n management-bastion \
     --target-resource-id "$(read_map_output vm_ids nva1)" --auth-type ssh-key \
     --username "$(read_output admin_username)" --ssh-key "$SSH_PRIVATE_KEY_FILE"
   ```

   Expect: A shell on `nva1` (repeat with `nva2` and `app`). Confirm hostname and private IP before changing anything.

2. **Check the application and prepare both NVAs**: `prepare` verifies ownership, saves the original underlay MTU, installs the **closed** bridge policy before bringing the ports up, and leaves health withdrawn. `advertise` is a separate decision.

   ```bash
   # on app (B)
   gwlb-app-ready
   # on nva1, then separately on nva2
   sudo gwlb-control status
   sudo gwlb-control prepare --confirm-guest-change
   sudo gwlb-control advertise --confirm-guest-change
   sudo gwlb-control status
   sudo gwlb-evidence
   ```

   Expect: Physical NIC outside the bridge; `gwlb-ext` 801/10801 and `gwlb-int` 800/10800; MTU 1550/1500; closed mode; no IP on bridge or tunnels; `/health` 200 after advertise.

## Activity 3: Attach the chain with the NSG envelope closed

**Goal.** Chain the public frontend to the Gateway Load Balancer while the application's test rule still denies, and record the control-plane state.

**Exam skill.** Prove the chain by its resource ID, not by seeing F in an output, and know why a chained but closed state is the safe start.

1. **Attach the chain with the envelope still closed**: Set `appliances_ready`, `application_ready` and `enable_chain` true; keep `test_paths_enabled` false. Then collect a fresh control-plane snapshot.

   ```bash
   EVIDENCE_PARENT=$(mktemp -d "$PWD/gwlb-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/chain-nsg-closed"
   ```

   Expect: `public-frontend` references exactly `inspection-gwlb/frontendIPConfigurations/inspection-frontend`; no outbound rule, NAT Gateway, public VM NIC, provider-consumer peering or UDR. `summary.txt` still says `chain_datapath_verification=NOT_PERFORMED`.

2. **Make the client configuration**: The file contains exactly `client_public_ip`, `consumer_public_ip` and `backend_ip`. Copy it and the probe to the approved client through an approved path.

   ```bash
   : "${CLIENT_CONFIG:?Set a NEW local JSON filename}"
   ./scripts/make-client-config.sh "$CLIENT_CONFIG"
   ```

   Expect: A new 0600 file. Documentation or private addresses are refused, and C must differ from P.

## Activity 4: Closed baseline

**Goal.** Open the test envelope, keep both bridges closed and capture one dropped attempt.

**Exam skill.** Explain why a negative test needs a healthy listener, an open envelope and a named counter before it counts as proof.

1. **Closed baseline**: Set `test_paths_enabled` true (bridges still closed and advertised). Start a bounded capture on both NVAs, then send one attempt.

   ```bash
   # each NVA
   sudo gwlb-evidence --capture --seconds 20 --packets 200 \
     --acknowledge-sensitive-capture
   # external client
   ./scripts/gwlb-probe closed --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
   ```

   Expect: Outer and decapsulated SYN on one NVA (X) and an increment of `deny-primary-8080-forward`. A timeout alone stays INCONCLUSIVE.

## Activity 5: First primary opening: observe, then close

**Goal.** Allow TCP 8080 on both NVAs for one bounded positive probe, record the real tuples, then close again.

**Exam skill.** Know that allow-primary has no timer, and that the first opening is a short observed window, not a standing policy.

1. **First primary opening: observe, then close**: `allow-primary` is persistent with no timer: a finished probe or a dropped SSH session does **not** close it.

   ```bash
   # BOTH NVAs, no client traffic while they differ
   sudo gwlb-control allow-primary --confirm-guest-change --acknowledge-capture-required
   sudo gwlb-control advertise --confirm-guest-change
   # external client, captures running
   ./scripts/gwlb-probe positive --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
   # BOTH NVAs, after captures release their lock
   sudo gwlb-control close --confirm-guest-change
   sudo gwlb-control status
   ```

   Expect: One complete fixture response; forward and return legs on the same X. Record the real inner destination (P or B). If anything is outside the model, stay closed and mark BLOCKED.

## Activity 6: Broader controls, stream and health withdrawal

**Goal.** In a second reviewed opening, run the positive, alternate and payload probes, then the optional stream and one-node health withdrawal.

**Exam skill.** Distinguish a policy Deny from a withdrawn health answer, and record the old-flow result from evidence.

1. **Broader controls in a second opening**: Only after reviewing step 8 and with new approval, repeat `allow-primary` and `advertise` on both NVAs.

   ```bash
   ./scripts/gwlb-probe positive --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
   ./scripts/gwlb-probe alternate --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
   ./scripts/gwlb-probe payload --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP" --bytes 262144
   ```

   Expect: Positive succeeds; alternate hits `deny-alternate-8081-forward` with 8081 healthy; payload size and SHA-256 match.

2. **Optional: stream and one-node health withdrawal**

   ```bash
   # external client
   ./scripts/gwlb-probe stream --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP" --duration 60
   # only on the identified X, with the other NVA healthy
   sudo gwlb-control withdraw-health --seconds 30 --confirm-guest-change
   ```

   Expect: New flows go to the other NVA. The old stream's fate is recorded, not assumed. Withdrawal leaves the nft table, counters and links unchanged and re-advertises after its checks.

## Activity 7: Restore closed, isolate, unchain and remove

**Goal.** Return to closed, isolate the application, detach the chain, and plan the removal in the order ownership needs.

**Exam skill.** Isolate first, then detach: the reverse order creates an inspection bypass.

1. **Restore closed and re-check**

   ```bash
   # BOTH NVAs
   sudo gwlb-control close --confirm-guest-change
   sudo gwlb-control status
   sudo gwlb-control advertise --confirm-guest-change
   # external client
   ./scripts/gwlb-probe closed --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP" --out "$CLIENT_EVIDENCE/closed-restored"
   # operator shell
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/closed-restored"
   ```

   Expect: A fresh named closed Deny, a new snapshot and a complete UTC timeline.

2. **Isolate the application: stop the fixtures on B**: Stop exactly the two fixture units and treat a failed query as a failure, never as nothing running. If any check fails, stop the teardown.

   ```bash
   sudo systemctl stop azure-gwlb-fixture@8080.service azure-gwlb-fixture@8081.service
   for unit in azure-gwlb-fixture@8080.service azure-gwlb-fixture@8081.service; do
     state=$(sudo systemctl show "$unit" --property=ActiveState --value) || exit 1
     [[ "$state" == inactive ]] || { printf 'Still active or uncertain: %s\n' "$unit" >&2; exit 1; }
   done
   listeners=$(sudo ss -H -ltn '( sport = :8080 or sport = :8081 )') || exit 1
   [[ -z "$listeners" ]] || { printf 'A test listener remains.\n' >&2; exit 1; }
   ```

   Expect: Both units inactive and no listener on 8080 or 8081.

3. **Close the NSG envelope with the chain still attached**: Set `test_paths_enabled = false`, keep `enable_chain = true`, then plan and review. Apply it through your approved change process, then collect a snapshot.

   ```bash
   terraform plan -input=false -var-file="$TFVARS" -out="$PLAN_DIR/close-nsg.tfplan"
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/pre-teardown-isolated"
   ```

   Expect: `test-client-ingress` is Deny in the effective NSG and old sessions have ended. A new Deny alone does not prove an old flow ended: test with fresh attempts.

4. **Only then detach the chain**: Set `enable_chain = false` in its own plan. Changing both flags in one plan does not guarantee a safe order.

   ```bash
   terraform plan -input=false -var-file="$TFVARS" -out="$PLAN_DIR/detach.tfplan"
   ```

   Expect: The plan changes only the `public-frontend` chain reference. **Detaching an open public consumer creates an inspection bypass**, so never do this before step 3 is proven.

5. **Optional: restore the NVAs**: On each NVA, remove only the owned bridge, tunnels and table and restore the recorded underlay MTU.

   ```bash
   sudo gwlb-control restore-original --confirm-guest-change
   ```

   Expect: Ownership checks pass and only the recorded MTU is restored. Pending or ambiguous records block the action.

6. **Plan the removal of everything the lab owns**: Review the destroy plan: the consumer, GWLB, three VMs and disks, three VNets and peerings, Bastion and two public IPs. Apply it only through your approved process, and keep Bastion until the last guest step. The image and SSH keys are not touched.

   ```bash
   terraform plan -destroy -input=false -var-file="$TFVARS" -out="$PLAN_DIR/destroy.tfplan"
   ```

   Expect: A plan that removes only lab resources. After an approved apply, `terraform state list` should be empty. Closing a rule or stopping a VM does not stop all charges.
