# Lab guide: Azure Route Server with BGP-peered Linux NVAs

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Route Server, Bastion and four VMs bill while they exist, and the lab ships no apply or destroy command.

## Activity 1: Prerequisites and local checks

**Goal.** Run every check that needs no Azure resources.

**Exam skill.** Know what must exist before any deployment, and what offline checks can and cannot prove.

1. **Local checks (no Azure)**: From the `lab/` folder.

   ```bash
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Source checks pass; the nine mocked plan cases run. `init` may download the provider. None of this proves Azure behaviour.

## Activity 2: Review a plan

**Goal.** Read a plan for the design's key facts without creating anything.

**Exam skill.** Check the plan for dedicated resources, the right image version, the route-table associations and cost. The lab ships no apply command.

1. **Review a plan**

   ```bash
   : "${APPROVED_INPUTS:?Set the reviewed private input-file path}"
   umask 077
   REVIEW_PLAN_DIR=$(mktemp -d "$PWD/rs-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$REVIEW_PLAN_DIR/review.tfplan"
   terraform show -no-color "$REVIEW_PLAN_DIR/review.tfplan" \
     > "$REVIEW_PLAN_DIR/review.txt"
   ```

   Expect: Only dedicated resources; correct image version, route-table associations and costs. The lab ships **no apply command**: deployment is a separately approved action.

## Activity 3: Scope check, closed baseline and route views

**Goal.** Prove the target, then record what Azure says is configured with no route exported.

**Exam skill.** Read Route Server learned and advertised routes in the right direction, and join them to effective routes.

1. **Scope check and closed baseline**: After an approved deployment, the runbook validates the subscription UUID, the Route Server resource ID, two distinct peer IPs in 10.0.1.0/26, a service ASN that is not 65010 and the destination values, then captures a baseline.

   ```bash
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   terraform output -json
   EVIDENCE_PARENT=$(mktemp -d "$PWD/rs-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/closed-baseline"
   ```

   Expect: RouteServerSubnet /26 without NSG/UDR; `peer-nva1` 10.0.2.4 and `peer-nva2` 10.0.2.5 at ASN 65010; branch-to-branch false; app propagation on, others off; NVA NICs forwarding; **no /24 learned**; A selects a None route for D.

2. **Read Route Server routes in the right direction**

   ```bash
   az network routeserver peering list-learned-routes \
     --subscription "$SUBSCRIPTION_ID" --resource-group "$RG" \
     --routeserver "$RS_NAME" --name peer-nva1 -o json
   az network routeserver peering list-advertised-routes \
     --subscription "$SUBSCRIPTION_ID" --resource-group "$RG" \
     --routeserver "$RS_NAME" --name peer-nva1 -o json
   az network nic show-effective-route-table --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name app-nic -o json
   ```

   Expect: *learned* = what Route Server received from the NVA; *advertised* = what Route Server sent to the NVA (VNet prefixes, which FRR denies). Keep per-instance entries.

## Activity 4: Connect, prove the fixtures and prepare each NVA

**Goal.** Reach the private VMs through Bastion, prove the destination fixtures and open forwarding on one NVA at a time.

**Exam skill.** Separate preparing forwarding from advertising the route, and know why a closed start is expected.

1. **Connect through Bastion**

   ```bash
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$BASTION" --target-resource-id "$REMOTE_VM_ID" \
     --auth-type ssh-key --username "$ADMIN" --ssh-key "$SSH_PRIVATE_KEY_PATH"
   ```

   Expect: A shell on R. Repeat for nva1, nva2 and A, and check `/etc/azure-routeserver-lab.json` before any node-specific action.

2. **Prove the fixtures and the closed start**: On R, then on each NVA.

   ```bash
   # R
   remote-ready
   sudo rs-control status
   sudo rs-evidence --capture-seconds 0
   # nva1, then nva2
   sudo rs-control status
   sudo rs-control check
   sudo vtysh -c 'show bgp ipv4 unicast summary json'
   ```

   Expect: Both fixtures answer locally with `azure-routeserver-origin-v1`. On the NVAs, `check` reports **not ready** (closed start is expected); both peers and the remote ASN match the outputs.

3. **Prepare each NVA (no export yet)**

   ```bash
   sudo rs-control prepare --confirm-guest-change
   sudo rs-control check
   sudo rs-control status
   ```

   Expect: Scoped forwarding open, export still false, tunnels up, D:8080 and D:8081 reachable through that node's own tunnel (a positive control, not proof that A can reach 8081).

## Activity 5: Advertise and run the positive and negative probes

**Goal.** Open the export on each NVA and prove the preferred path with evidence.

**Exam skill.** Prove a path with the attempted tuple, the translated tuple and both-node evidence; prove a drop with the rule counter.

1. **Advertise each NVA**: Only after all four sessions are Established.

   ```bash
   sudo rs-control advertise --confirm-guest-change
   sudo rs-control check
   # operator shell
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/preferred-advertised"
   ```

   Expect: Both RS instances learned 172.20.50.0/24 from both NVAs with paths 65010 and 65010 65010 65010; A's next hop is 10.0.2.4. Do not use a fixed sleep as proof of convergence.

2. **Capture, then run the positive and negative probes**

   ```bash
   # nva1, nva2 and R, each in its own session
   sudo rs-evidence --capture-seconds 90
   # A
   APP_EVIDENCE=$(mktemp -d "$HOME/rs-client-XXXXXXXX")
   rs-probe positive --expected-node nva1 --out "$APP_EVIDENCE/preferred-positive"
   rs-probe negative --expected-node nva1 --out "$APP_EVIDENCE/preferred-negative"
   ```

   Expect: Positive: HTTP 200, correct marker and case, R saw `10.255.1.1:q`, conntrack/SNAT and GRE1 evidence on nva1. Negative: SYN seen on nva1 and the `deny-alternate-8081` counter increased.

## Activity 6: Failure experiments and recovery

**Goal.** Break the design one way at a time and recover deliberately.

**Exam skill.** Tell apart a withdrawal, one lost session, BGP alive with forwarding dead, and all exports withdrawn.

1. **Withdraw nva1 for a bounded time (backup-only positive)**: Run on nva1. The helper holds an exclusive lock for the window and restores on HUP, INT or TERM. Then probe from A once A's next hop is measured as N2.

   ```bash
   sudo rs-control withdraw-for --seconds 90 --confirm-guest-change
   # A, once A's next hop is measured as N2
   rs-probe positive --expected-node nva2 --out "$APP_EVIDENCE/backup-positive"
   ```

   Expect: R sees S2 and GRE2. A fresh request through nva2 succeeds. This is a new connection, not a migrated one.

2. **Hold a stream across a withdrawal**: Start the stream on A, then withdraw nva1 as in step 1 during the window.

   ```bash
   rs-probe stream --duration 120 --expected-node nva1 \
     --out "$APP_EVIDENCE/preferred-stream-withdrawal"
   ```

   Expect: The old socket fails or stalls (no state on nva2). Fresh requests through nva2 succeed. Record old and new flows separately.

3. **Lose one BGP session only**: Take the peer IP from the actual sorted Route Server output.

   ```bash
   RS_PEER='REPLACE_WITH_ONE_ACTUAL_ROUTE_SERVER_PEER_IPV4'
   sudo rs-control session-down-for --peer "$RS_PEER" --seconds 60 --confirm-guest-change
   ```

   Expect: The other session keeps the route, so A's next hop should stay N1. Observe it; do not assume it.

4. **BGP alive, forwarding dead**: Closes the data policy while the export stays unchanged.

   ```bash
   sudo rs-control fail-forwarding --seconds 30 --confirm-guest-change
   ```

   Expect: Sessions stay up and A's next hop stays N1 while packets are dropped. There is no automatic health-to-BGP withdrawal.

5. **Withdraw everything**: Run on nva1, then on nva2.

   ```bash
   sudo rs-control withdraw --confirm-guest-change
   ```

   Expect: A's longest match for D becomes 172.16.0.0/12 → None. There is no Internet fallback.

6. **Recover or close deliberately**: Pick ONE action, on the affected NVA only, after the bounded operation has released its lock. Never delete a lock or marker file.

   ```bash
   sudo rs-control reconcile --confirm-guest-change        # clear an uncertain transition
   sudo rs-control recover --confirm-guest-change          # restore recorded prior state
   sudo rs-control close --confirm-guest-change            # deliberate containment
   sudo rs-control restore-original --confirm-guest-change # owned sysctls only
   ```

   Expect: Run `status` again, then confirm the withdrawal at both Route Server instances and on A independently. Recover may reopen forwarding and re-export a saved baseline, so approve that consequence first.

## Activity 7: Withdraw, close and destroy

**Goal.** Withdraw and close the data path, then remove everything with approval and verify it is gone.

**Exam skill.** Know that a withdrawn route does not stop billing, and that deleting the state file deletes nothing in Azure.

1. **Stop traffic and withdraw on both NVAs**

   ```bash
   sudo rs-control withdraw --confirm-guest-change
   ```

   Expect: Then verify the withdrawal at both Route Server instances and on A's effective routes before the next step.

2. **Close the guest data path**

   ```bash
   sudo rs-control close --confirm-guest-change
   sudo rs-control restore-original --confirm-guest-change
   ```

   Expect: Forwarding closed. `restore-original` only restores the owned sysctls; it requires no pending recovery record and removes nothing else.

3. **Save evidence, then destroy with approval**: Save a final control snapshot and guest evidence. Then review a complete destroy plan for the dedicated state and resource group through your approved workflow (the lab ships no destroy command). Do not delete the gallery image, operator keys or any shared hub or gateway.

   ```bash
   terraform plan -destroy -input=false -var-file="$APPROVED_INPUTS" \
     -out="$REVIEW_PLAN_DIR/destroy.tfplan"
   terraform show -no-color "$REVIEW_PLAN_DIR/destroy.tfplan"
   ```

   Expect: Only lab resources removed. Deleting the state file does **not** delete Azure resources; check for leftover disks, public IPs, Bastion and Route Server. Review the destroy plan; the lab ships no destroy command, so applying it is a separately approved action.
