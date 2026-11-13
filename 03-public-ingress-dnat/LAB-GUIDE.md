# Lab guide: publish a private service with Azure Firewall DNAT

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall and Bastion bill while they exist. With `publish_dnat = true` a plain-HTTP test service is reachable from one approved public address: send no credentials or real data.

## Activity 1: Prerequisites and local checks

**Goal.** Confirm the right subscription and run every check that needs no deployment.

**Exam skill.** Know what must exist before a deployment: providers, extensions, image, region capacity, and a configuration that is checked offline.

1. **Prepare and validate offline**: Copy the example inputs, fill in subscription, region, concrete image version, your /32 and owner tag. Keep `publish_dnat = false`.

   ```bash
   cd lab
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass; the eleven mocked plan tests pass. Note: `init -backend=false` can still download the provider — use an approved source or mirror.

2. **Run the read-only preflight**: Confirm extensions, provider registration and capacity in the approved subscription and region.

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   : "${SUBSCRIPTION_ID:?Set the approved subscription UUID before preflight}"
   : "${REGION:?Set the reviewed region matching terraform.tfvars}"
   az extension list --query '[].{name:name,version:version}' -o table
   az provider show --namespace Microsoft.Network --query registrationState -o tsv --subscription "$SUBSCRIPTION_ID"
   az vm list-skus --location "$REGION" --size Standard_B1s --all -o table --subscription "$SUBSCRIPTION_ID"
   ```

   Expect: Required extensions listed, providers `Registered`, the VM size available. Repeat `provider show` for Compute, OperationalInsights and Insights.

## Activity 2: Plan, review and deploy unpublished

**Goal.** Preview what Terraform will create, check it against the design, and (only when approved) build it with nothing published yet.

**Exam skill.** Read a plan for the design's key facts: no VM public IP, two public IPs, computed firewall IP in the route, `publish_dnat = false`.

1. **Plan, review, stop**: Review identity, cost, the unpublished state, no NIC public IP, both peerings, the NSG and route associations. Deployment needs separate authorization.

   ```bash
   terraform plan -out=lab.tfplan
   terraform show -no-color lab.tfplan
   ```

   Expect: No `test-rules` group (unpublished); `db-inspect` holds one route `0.0.0.0/0 → VirtualAppliance`; two Standard public IPs (firewall, Bastion).

2. **Apply only after approval**: Deployment needs separate authorization. When it is given, apply the reviewed plan with `publish_dnat` still `false`: the firewall, Bastion, the VM and the logs are created, but nothing is published.

   ```bash
   terraform apply lab.tfplan
   terraform output
   ```

   Expect: Outputs include `firewall_public_ip`, `firewall_private_ip`, `backend_vm_id`, `bastion_name` and `workspace_customer_id`. `public_http_url` is null while unpublished. Billing has started.

## Activity 3: Record the configuration and check the fixture

**Goal.** Save what Azure says is configured, then reach the private VM through Bastion and confirm the test service is ready locally.

**Exam skill.** Separate configuration from behavior, and separate local readiness from public DNAT.

1. **After authorized deployment: capture the control plane**: The collector reads firewall, policy, groups, NICs, subnets, peerings, route table, effective routes and NSGs, pinned to the subscription inside `firewall_id`.

   ```bash
   ./scripts/collect-control-plane.sh
   terraform output experiment_settings
   P=$(terraform output -raw firewall_public_ip)
   F=$(terraform output -raw firewall_private_ip)
   ALLOWED=$(terraform output -raw allowed_client_cidr)
   ```

   Expect: Evidence folder under `evidence/control-<UTC>`; P and F are real values (not documentation addresses).

2. **Open a private session and check the fixture**: The README first checks that the subscription inside `firewall_id` equals `SUBSCRIPTION_ID` and stops if not. Then:

   ```bash
   RG=$(terraform output -raw resource_group_name)
   BASTION=$(terraform output -raw bastion_name)
   USER_NAME=$(terraform output -raw admin_username)
   DB_ID=$(terraform output -raw backend_vm_id)
   az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$DB_ID" --subscription "$SUBSCRIPTION_ID" \
     --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
   # inside B
   cloud-init status --wait
   sudo /usr/local/bin/dnat-ready
   curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.20.1.10:8080/ready-local
   ```

   Expect: HTTP 200 with the fixture's identity. Here the peer is B itself — that is normal for a local check and says nothing about DNAT.

## Activity 4: Publish and send the positive request

**Goal.** Turn the publication on, send one request from the approved client and prove each of the three facts: NAT row, backend peer I, and the return route.

**Exam skill.** Explain why the backend sees I and not C, and why the reply uses the peering /16.

1. **Publish**: Set `publish_dnat = true` (keep `enable_default_route = true`, `return_route_blackhole = false`), review the new plan and apply it through the approved workflow. Re-run the collector.

   Expect: Exactly one group `test-rules` (200) → `publish-test` (100) → `operator-only`: your /32 → P:8443 ⇒ 10.20.1.10:8080.

2. **Positive request from the approved client**: Set C to the client network's real public IPv4 (not the laptop's private address).

   ```bash
   : "${P:?Set actual lab firewall public IPv4}"
   : "${ALLOWED:?Set the actual approved public IPv4/32}"
   : "${C:?Set the current client actual public IPv4}"
   ./scripts/client-probe.sh positive "$P" "$ALLOWED" "$C"
   ```

   Expect: `TRANSLATED_FIXTURE_IDENTITY=MATCH`, `Observed backend peer I:q=` an address in 10.0.1.0/26, then `RESULT=NEEDS_REVIEW` (always printed).

3. **Prove the return route to the observed I**: Read I from the matching case in the backend journal (not from `/ready-local`), then ask Network Watcher for B's next hop to it.

   ```bash
   sudo journalctl -u azure-dnat-fixture.service --since '10 minutes ago' --utc --no-pager -o cat
   # management workstation
   : "${I:?Set observed backend peer IP from the external case}"
   az network watcher show-next-hop -g "$RG" --vm db --nic db-nic --subscription "$SUBSCRIPTION_ID" \
     --source-ip 10.20.1.10 --dest-ip "$I" -o json
   ```

   Expect: The selected route is the hub peering 10.0.0.0/16, not the /0 UDR. If no Network Watcher exists, mark this NOT RUN — do not create one.

4. **Read the NAT row for the case**: Fill the firewall resource ID and P into the query, then run it with the Azure CLI (or paste the query into the portal's Logs blade). Ingestion can lag up to 30 minutes.

   ```bash
   FW_ID=$(terraform output -raw firewall_id)
   WORKSPACE=$(terraform output -raw workspace_customer_id)
   mkdir -p evidence
   sed -e "s|FIREWALL_RESOURCE_ID|$FW_ID|g" \
       -e "s|ACTUAL_FIREWALL_PUBLIC_IPV4|$P|g" queries/nat.kql > evidence/nat.kql
   az monitor log-analytics query --workspace "$WORKSPACE" --subscription "$SUBSCRIPTION_ID" \
     --analytics-query "$(cat evidence/nat.kql)" -o json > evidence/nat-rows.json
   ```

   Expect: One row: SourceIp C, DestinationIp P, port 8443, TranslatedIp 10.20.1.10, TranslatedPort 8080, rule `operator-only`. There is no Action column and no translated-source column; I:q comes from the backend journal.

## Activity 5: Negative tests with controls

**Goal.** Show that an unpublished port and a source outside the /32 are not served, with positive controls before and after.

**Exam skill.** Know that a negative needs controls because unmatched traffic writes no NAT row.

1. **Negatives with controls**: Unpublished port from C, then a positive control. Excluded source only from the second network.

   ```bash
   ./scripts/client-probe.sh unpublished-port "$P" "$ALLOWED" "$C"
   ./scripts/client-probe.sh positive "$P" "$ALLOWED" "$C"
   # from the second, excluded network:
   ./scripts/client-probe.sh excluded-source "$P" "$ALLOWED" "$C2"
   ```

   Expect: No fixture response for 8444 or from C2; no NAT row for either; the 8443 control still succeeds.

## Activity 6: Experiments: break it on purpose (optional)

**Goal.** Change one thing at a time to see what the return path really depends on.

**Exam skill.** Tell a policy match, a route and a listener apart.

1. **Listener unavailable, then restore**: Run the block below in B's Bastion session; while it waits, run `./scripts/client-probe.sh listener-unavailable "$P" "$ALLOWED" "$C"` from C, then press Enter.

   ```bash
   # Controlled listener contrast: owned service only; restore on normal/error exit.
   (
     set -euo pipefail
     service=azure-dnat-fixture.service
     sudo /usr/local/bin/dnat-ready
     restore_fixture() {
       status=$?
       trap - EXIT HUP INT TERM
       if sudo systemctl start "$service"; then
         if sudo /usr/local/bin/dnat-ready; then
           printf 'Owned fixture restored and locally ready.\n'
         else
           printf 'ERROR: fixture started but readiness failed; investigate before continuing.\n' >&2
           status=1
         fi
       else
         printf 'ERROR: owned fixture restart failed; manual recovery required.\n' >&2
         status=1
       fi
       exit "$status"
     }
     trap restore_fixture EXIT
     trap 'exit 130' INT
     trap 'exit 143' HUP TERM
     sudo systemctl stop "$service"
     if sudo systemctl is-active --quiet "$service"; then
       printf 'ERROR: fixture remains active; aborting contrast.\n' >&2
       exit 1
     fi
     printf 'Run the listener-unavailable probe from C now. Press Enter to restore; auto-restore after 60 seconds.\n'
     if read -r -t 60 _; then
       :
     else
       printf 'Contrast window ended; attempting restoration.\n'
     fi
   )
   ```

   Expect: `Owned fixture restored and locally ready.` If restoration is not confirmed, run `sudo systemctl start azure-dnat-fixture.service` and `sudo /usr/local/bin/dnat-ready` from a second session.

2. **Remove the workload default route, then restore**: Change only `enable_default_route = false`, review the plan, run a fresh `positive` probe, then restore the flag and re-verify.

   ```bash
   terraform plan -var 'enable_default_route=false' -out=noroute.tfplan
   terraform show -no-color noroute.tfplan
   ```

   Expect: The plan deletes `azurerm_route.backend["default"]`. After an approved apply the positive probe still succeeds, because the reply to I uses the hub peering /16.

3. **Return blackhole, then restore**: Change only `return_route_blackhole = true`. The added route is `10.0.1.0/26 → None`, more specific than the hub peering /16. Probe, then set the flag back to `false`.

   ```bash
   terraform plan -var 'return_route_blackhole=true' -out=hole.tfplan
   ./scripts/client-probe.sh return-blackhole "$P" "$ALLOWED" "$C"
   ```

   Expect: Effective routes show the `None` route; a NAT row can still appear, the handshake fails and there is usually no backend HTTP row. This is a return-routing failure, not a DNAT-policy deny. Restore the flag, confirm the /26 is gone, then rerun readiness and a fresh positive.

## Activity 7: Withdraw, destroy and verify

**Goal.** Stop the exposure, save the evidence, remove everything and prove it is gone.

**Exam skill.** Know that withdrawing the DNAT rule stops exposure but not billing, and that stopping the VM does not stop firewall or Bastion charges.

1. **Withdraw the publication**: Set `publish_dnat = false`, review and apply. Confirm the group is gone, then probe.

   ```bash
   ./scripts/client-probe.sh publication-withdrawn "$P" "$ALLOWED" "$C"
   ```

   Expect: No fixture response. Billing for Firewall, Bastion and the VM continues until you destroy the lab.

2. **Save evidence off the VM**: Export only the fixture journal and readiness output to `~/dnat-evidence` on B, then copy it through a Bastion tunnel.

   ```bash
   az network bastion tunnel -g "$RG" -n "$BASTION" --target-resource-id "$DB_ID" --subscription "$SUBSCRIPTION_ID" \
     --resource-port 22 --port 50022
   # another local terminal
   scp -P 50022 -i "$HOME/.ssh/your-approved-key" -r \
     "$USER_NAME@127.0.0.1:/home/$USER_NAME/dnat-evidence" ./evidence/backend
   ```

3. **Plan the destroy and stop for approval**: Repeat the subscription check first.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   ```

4. **After the approved destroy, verify**: Look for leftovers: Firewall, Bastion, public IPs, VM/OS disk, policy, peerings, workspace.

   ```bash
   terraform state list
   az group exists --name "$RG" --subscription "$SUBSCRIPTION_ID"
   ```

   Expect: Empty state and `false` — only after a completed deletion. Do not purge retained logs as part of clean-up.
