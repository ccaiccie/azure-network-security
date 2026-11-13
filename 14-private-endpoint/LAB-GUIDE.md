# Lab guide: Azure Firewall application inspection for a Blob private endpoint

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall, Bastion and the private endpoint bill while they exist. Commands marked *added in this edition* are not in the original README.

**Edition notes.** `terraform fmt` was applied to the Terraform files; nothing else was run (no `init`, `plan` or `apply`). It aligns the `=` signs, which broke one spacing-sensitive text check in `tests/source_contract.py`; that test now collapses whitespace around `=` before it compares. After the change all 144 source assertions and all 88 offline unit tests pass again.

## Activity 1: Offline checks, plan and deploy the closed substrate

**Goal.** Check everything that needs no deployment, then build only the closed substrate.

**Exam skill.** Know what must exist before a deployment, and read a plan for the design's key facts: no VM public IP, Blob public access Disabled, and F computed rather than assumed.

1. **Run the offline checks**: From the `terraform` folder. These are source, shell, Python and mocked checks only. `terraform fmt` was already applied in this edition (see the edition notes). Provider checks are for a separately approved preparation environment; the lab supplies no apply or destroy command on purpose.

   ```bash
   bash scripts/check-local.sh
   # later, in an approved preparation environment (NOT RUN so far):
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass. Record any provider step you could not run; never fabricate a lock file.

2. **Prepare the variables (added in this edition)**: Copy the example file and replace the placeholders: `subscription_id`, `location`, `storage_account_name`, `ssh_public_key` (public key only) and `image_id`. For the closed substrate set only `deploy_lab`, `image_prerequisites_confirmed` and `identity_access_authorized` to `true`; every other gate stays `false`, `install_pe_host_route` stays `true` and `pe_network_policies` stays `"Enabled"`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars: real values, three gates true
   ```

   Expect: A `terraform.tfvars` with no secrets, passwords, keys or SAS in it.

3. **Review the plan (added in this edition)**: A plan is a preview that creates nothing. Check it against the design before you go on: the right subscription and region, only lab resources, no public IP on a VM, one public IP for the firewall and one for Bastion, public network access Disabled on the account, and a cost you accept.

   ```bash
   terraform plan -out=closed.tfplan
   terraform show -no-color closed.tfplan
   ```

   Expect: A plan with only the closed substrate. Stop here unless deployment is approved.

4. **Apply the closed substrate and read the outputs (added in this edition)**: Apply the saved plan through your approved process. The firewall takes many minutes. Cloud-init only writes `/etc/azure-pe-lab.json` and the helpers. Then read the outputs; F is allocated here and is not a value to assume.

   ```bash
   terraform apply closed.tfplan
   terraform output firewall_private_ip
   ```

   Expect: Infrastructure and two distinct identities exist; no data role, token, blob or open Blob path. The output shows the allocated F in 10.0.1.0/26.

## Activity 2: Take the control-plane snapshot and log in through Bastion

**Goal.** Save what Azure says is configured, and reach the private VMs without a public IP.

**Exam skill.** Prove the design with the control plane (approval state, effective routes, zone group) and keep management outside the inspection path.

1. **Validate the outputs, then take a control-plane snapshot**: `load_context` refuses to continue unless every resource ID, VM/NIC map, fixed address, identity and a usable F in 10.0.1.0/26 match the intended design.

   ```bash
   export SUBSCRIPTION_ID='<approved subscription UUID>'
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   source ./scripts/common.sh
   load_context
   az account show --subscription "$SUBSCRIPTION_ID" \
     --query '{subscription:id,tenant:tenantId,name:name}' -o json
   RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
   CONTROL_ROOT="$PWD/evidence/$RUN_ID"
   mkdir -p -- "$CONTROL_ROOT"
   ./scripts/collect-control-plane.sh "$CONTROL_ROOT/01-closed"
   ```

   Expect: `summary.txt` with `collection_failures=0` and `route_verification`, `inspection_verification`, `blob_access_verification` all `NOT_PERFORMED`. Never edit those into a pass.

2. **Log in through Bastion and review the endpoint**: Use `seed` in a separate session when needed. Check: PE `Approved`, exact Storage ID, `blob` subresource, E, subnet policies, zone group record. An empty `customDnsConfigs` can be normal with a valid zone group.

   ```bash
   ROLE=reader  # repeat with seed in its own session when needed
   case "$ROLE" in reader|seed) ;; *) exit 2 ;; esac
   : "${SSH_USERNAME:?Set the approved VM username}"
   : "${SSH_KEY_PATH:?Set the path to the existing approved local SSH key}"
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$(read_output bastion_name)" \
     --target-resource-id "$(read_map_output vm_ids "$ROLE")" \
     --auth-type ssh-key --username "$SSH_USERNAME" \
     --ssh-key "$SSH_KEY_PATH"
   ```

   Expect: Then record `pe_ready = true`.

## Activity 3: Open DNS only and check the route

**Goal.** Prove that both clients resolve the ordinary hostname to E, and see the next hop for E.

**Exam skill.** Separate DNS from path: a private answer is not permission, and the next hop must show the firewall F.

1. **Open DNS only and run the readiness helper on each guest**: Set `dns_enabled = true`, then run this on the reader and, separately, on the seed. The subshell keeps the helper's exit code and timing, so a failure is never hidden by the final `cat`. `pe-ready` checks the NIC, the CA bundle, OS resolution and `dig @F`; no token, TLS or Blob request.

   ```bash
   umask 077
   RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
   GUEST_ROOT="$HOME/pe-evidence/$RUN_ID"
   mkdir -p -- "$GUEST_ROOT"
   (
     set -eu
     READY_OUT="$GUEST_ROOT/01-ready"
     mkdir -- "$READY_OUT"
     date -u +%FT%TZ > "$READY_OUT/started-utc.txt"
     if pe-ready > "$READY_OUT/readiness.json" 2> "$READY_OUT/readiness.stderr"; then
       rc=0
     else
       rc=$?
     fi
     printf '%s\n' "$rc" > "$READY_OUT/exit.txt"
     date -u +%FT%TZ > "$READY_OUT/completed-utc.txt"
     cat "$READY_OUT/readiness.json"
     exit "$rc"
   )
   ```

   Expect: `LOCAL_DNS_CLIENT_READY` with only E in the answers. This is not a TLS or path verdict. Then record `dns_verified = true`.

2. **Verify the route with Network Watcher (optional)**: Repeat for the seed (10.10.1.11). Only if Network Watcher already exists; never create it here. The effective routes in the snapshot are the primary evidence.

   ```bash
   az network watcher show-next-hop --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vm "$(read_map_output vm_ids reader)" \
     --nic "$(read_map_output nic_ids reader)" \
     --source-ip 10.10.1.10 --dest-ip 10.30.1.7 -o json
   ```

   Expect: `VirtualAppliance` with the actual F; the endpoint /32 visible as the overridden competitor. Then record `routes_verified = true`.

## Activity 4: Named firewall Deny, then anonymous reachability

**Goal.** See the firewall alone stop the reader, then flip one rule and see a genuine Blob error.

**Exam skill.** Tell a named application Deny from a service error, and know that a 403 alone proves neither the private path nor inspection.

1. **Named firewall Deny baseline (reader)**: Set `pe_ingress_enabled` and `client_paths_enabled` true; `allow_client_blob` stays false.

   ```bash
   pe-probe noauth --out "$GUEST_ROOT/02-firewall-deny"
   ```

   Expect: No service response; a `reader-to-owned-blob` **Deny** row matching A, the source port and time. No service request ID is expected.

2. **Anonymous reachability, then close**: Set only `allow_client_blob = true`. Afterwards restore Deny, prove it with a fresh noauth run, and set `client_paths_enabled = false` before any token-bearing step.

   ```bash
   pe-probe noauth --out "$GUEST_ROOT/03-noauth-reachability"
   ```

   Expect: Peer E, valid certificate for H, a genuine Blob error with safe metadata, a named **Allow** row. Not object access.

## Activity 5: Seed the proof object, then read it

**Goal.** Create the fixed proof object from the seed VM, then read it with the reader's token.

**Exam skill.** Keep reachability, inspection and authorization as three separate claims, each with its own evidence.

1. **Seed the proof object from W (separately approved)**: Enable `grant_seed_role`, `seed_paths_enabled` and `allow_seed_blob`; keep the reader closed. The flags acknowledge approvals you already have; they grant nothing.

   ```bash
   pe-probe seed --confirm-token-use --confirm-data-operation \
     --out "$GUEST_ROOT/02-seed-create"
   ```

   Expect: HTTP 201 → `CREATE_ACCEPTED`. Then close in order: `allow_seed_blob`, `seed_paths_enabled`, `grant_seed_role`.

2. **Reader read and the authorization negative**: Enable `grant_reader_role`, then reopen `client_paths_enabled` and `allow_client_blob`.

   ```bash
   pe-probe read --confirm-token-use --out "$GUEST_ROOT/04-read-content"
   pe-probe noauth --out "$GUEST_ROOT/05-auth-negative"
   ```

   Expect: Read: HTTP 200, all 51 bytes, matching SHA256 → `authorized_blob_read_proven=true`, while `private_path_proven` and `firewall_inspection_proven` stay false and `outcome=NEEDS_REVIEW`. Noauth: a genuine service rejection.

## Activity 6: Restore the Deny, isolate and observe the route contrast

**Goal.** Close the paths in order and (optionally) watch the endpoint route come back without any traffic.

**Exam skill.** Know why removing the /32 UDR makes the direct path the selected route, and why it is only observed with all Blob paths closed.

1. **Restore Deny and isolate both clients**: Set `allow_client_blob = false` while the envelope is still open, prove the named Deny, then close client, seed and PE ingress paths and remove both role grants.

   ```bash
   pe-probe noauth --out "$GUEST_ROOT/06-restored-firewall-deny"
   ```

   Expect: Named Deny on a fresh flow; all Blob envelopes closed; probe processes finished.

2. **Optional: isolated route contrast (no Blob traffic)**: With `isolation_verified` and `route_experiment_acknowledged` true, set `install_pe_host_route = false`, collect, restore the /32 and collect again. Change one setting at a time.

   ```bash
   ./scripts/collect-control-plane.sh "$CONTROL_ROOT/02-isolated-route-contrast"
   ```

   Expect: Without the /32 UDR the endpoint's /32 InterfaceEndpoint route is active again on both client NICs. Restore `Enabled` and the /32 before any reopening.

## Activity 7: Read the firewall, DNS and Storage logs

**Goal.** Turn the evidence into a verdict with Log Analytics.

**Exam skill.** Correlate tuple, time, rule and request ID; know that the firewall and Storage logs cannot be joined on a header.

1. **Run the application-rule query (added in this edition)**: The lab's `queries/application-rule.kql` is a starting point with placeholder values. Copy it, replace the time window, the hostname H and (if you wish) the source address, then run it against the workspace. `az monitor log-analytics query` may need the `log-analytics` extension; with dynamic install disabled, install it through your normal approved process. The portal's Logs blade runs the same query.

   ```bash
   cp queries/application-rule.kql "$CONTROL_ROOT/application-rule.kql"   # edit start, end and host first
   az monitor log-analytics query --workspace "$(read_output workspace_customer_id)" \
     --analytics-query "$(cat "$CONTROL_ROOT/application-rule.kql")" -o json > "$CONTROL_ROOT/application-rule.json"
   ```

   Expect: Rows for A or W with collection `reader-blob` or `seed-blob`, rule `reader-to-owned-blob` or `seed-to-owned-blob`, the action at the probe's source port and time, and `IsTlsInspected` false. An empty result is inconclusive: ingestion can lag.

2. **Run the DNS-proxy query (added in this edition)**: Proves that the guests asked the firewall. Use the `AZFWDnsQuery` query from the Evidence section with the same time window and run it the same way. The table records query and error metadata, not the A-record answer, so keep the guest's own `pe-ready` answers.

   ```bash
   az monitor log-analytics query --workspace "$(read_output workspace_customer_id)" \
     --analytics-query "$(cat "$CONTROL_ROOT/dns-proxy.kql")" -o json > "$CONTROL_ROOT/dns-proxy.json"
   ```

   Expect: Rows from 10.10.1.10 and 10.10.1.11 for the ordinary hostname. A cached answer may produce no new row.

3. **Join the Blob operation by the client request ID (added in this edition)**: `queries/blob-service.kql` selects the owned account and one case UUID, the value the probe sent in `x-ms-client-request-id` (read it from the probe's `result.json`). Edit the placeholders, run it, then label each claim separately: reachability, inspection, authorization, exact content and closure.

   ```bash
   cp queries/blob-service.kql "$CONTROL_ROOT/blob-service.kql"   # edit start, end, account and caseId first
   az monitor log-analytics query --workspace "$(read_output workspace_customer_id)" \
     --analytics-query "$(cat "$CONTROL_ROOT/blob-service.kql")" -o json > "$CONTROL_ROOT/blob-service.json"
   ```

   Expect: A row with the operation, status, authentication type and requester object ID. A request blocked before HTTP has no row. `CallerIpAddress` is an observation, never to be rewritten as F.

## Activity 8: Close the gates and clean up

**Goal.** Close the paths in dependency order, then remove only the lab's own resources.

**Exam skill.** Know that closing a gate does not stop billing, and that deleting steering first would reopen the direct route.

1. **Stop the work and restore both named Denies**: Let known probe processes finish (they are finite) or interrupt only those exact processes. Then set `allow_client_blob = false` and `allow_seed_blob = false` in `terraform.tfvars`, review and apply the change, and prove the Deny with a fresh noauth run while the envelope is still open. The firewall drops affected sessions when a rule changes to Deny, but observe it. A missing result after an interruption is incomplete: do not assume a PUT was rejected.

   ```bash
   # edit terraform.tfvars: allow_client_blob = false, allow_seed_blob = false
   terraform plan -out=close1.tfplan   # added in this edition
   terraform apply close1.tfplan       # added in this edition
   pe-probe noauth --out "$GUEST_ROOT/07-final-deny"
   ```

   Expect: A named Deny row on a fresh flow; no probe process left running.

2. **Close the client paths and the endpoint ingress**: Set `client_paths_enabled`, `seed_paths_enabled` and `pe_ingress_enabled` to `false`, then review and apply. An NSG change may not end established flows, so check that the sessions really ended.

   ```bash
   terraform plan -out=close2.tfplan   # added in this edition
   terraform apply close2.tfplan       # added in this edition
   ```

   Expect: Both NIC NSG rules 100 and `endpoint-nsg` rule 100 show Deny; no session survives.

3. **Revoke only the lab roles**: Set `grant_seed_role` and `grant_reader_role` to `false` after their Allows are `false` (validation rejects removing the seed role while `allow_seed_blob` is true). Issued tokens are not instantly invalidated, and IMDS stays open.

   ```bash
   terraform plan -out=close3.tfplan   # added in this edition
   terraform apply close3.tfplan       # added in this edition
   ```

   Expect: No role assignment of the lab's identities remains on the container.

4. **Decide the data and clear the attestations**: `lab-data/proof.txt` belongs only to this lab; one-day soft delete does not survive deleting the account, and permanent deletion needs its own approval (the helper never deletes). Keep `E/32 → F`, `Enabled`, DNS and management until both VMs are isolated. Then, with every Allow and path `false`, set `dns_enabled` to `false`, then clear `dns_verified`, `routes_verified` and `pe_ready`, restore `install_pe_host_route = true` and `Enabled`, and clear the experiment acknowledgments.

   Expect: Every gate `false` except deploy; baseline settings restored. Neither removing the route nor disabling policies is an emergency isolation action.

5. **Remove only the owned resources**: Review a removal plan for this lab's account, endpoint, zone and link, policy, firewall, VMs and identities, routes, peerings, workspace and Bastion. `deploy_lab = false` after a deployment means destroy, not pause. Keep management until the last observation, and never use clean-up to remove unrelated roles or data.

   ```bash
   # edit terraform.tfvars: deploy_lab = false
   terraform plan -out=remove.tfplan   # added in this edition
   terraform show -no-color remove.tfplan   # added in this edition
   terraform apply remove.tfplan   # added in this edition
   ```

   Expect: A plan that removes only lab resources, then an apply that completes.

6. **Verify that nothing billable remains (added in this edition)**: Check the resource group and the Storage account with approved reads, and look for leftover public IPs, disks, private endpoints and workspace data. Retain private state and evidence only under your authorised retention policy; the state can hold keys even though Shared Key is disabled.

   ```bash
   az group exists --name "$RG"
   ```

   Expect: `false`. Actual clean-up has never been run for this lab.
