# Lab guide: layered WAF with Azure Front Door and Application Gateway

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Front Door Premium, the WAF_v2 gateway, the Standard public IP and the B1 App Service plan bill while they exist, and closing gates does not stop billing.

## Activity 1: Prerequisites, review and offline checks

**Goal.** Review the sources, run every check that needs no Azure call, and build the fixture archive.

**Exam skill.** Know what must be true before any deployment: the certificate, the identity, DNS control and the client address are yours to supply.

1. **Review sources and run the offline checks**: Supply the real subscription, region, unique names, C/32, Horigin, identity ID and versionless secret URI in `terraform.tfvars` (never a key or password). Then run only the local checks and build the fixture ZIP.

   ```bash
   cd /path/to/reviewed/scenario15/lab
   ./scripts/check-local.sh
   python3 scripts/build-origin.py
   python3 -m zipfile -l build/origin.zip
   sha256sum build/origin.zip
   ```

   Expect: Local checks pass; `build/origin.zip` contains only `package.json` and `server.js`; record the SHA-256 for independent review. This is not Azure validation.

2. **Provider checks (future, in an authorised environment)**

   ```bash
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Format, schema and mock-plan checks pass. `init` downloads the provider, so it needs approval. These were **not run** for the original lab.

## Activity 2: Deploy the closed substrate and record context

**Goal.** Create the lab with every path closed and save what Azure says is configured.

**Exam skill.** Read a closed substrate: listener present, NSG user ingress denied, main site and SCM closed, edge route disabled.

1. **Apply the closed substrate**: Apply a reviewed plan with only `deploy_lab=true` and `certificate_access_confirmed=true`, through your own approved workflow (the original lab supplies no apply command). The listener exists, but NSG user ingress, the edge route, the main site and SCM stay closed.

   Expect: Azure Front Door, the gateway, the App Service and the workspace exist, with every other gate false.

2. **Scope the shell and record context**: Scope the shell to the approved subscription, load the context guard and collect a first control-plane snapshot.

   ```bash
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   source ./scripts/common.sh
   load_context
   az account show --subscription "$SUBSCRIPTION_ID" \
     --query '{id:id,name:name,tenantId:tenantId}' --output json
   umask 077
   CASE_ROOT=$(mktemp -d "$HOME/waf-evidence-XXXXXXXX")
   export CASE_ROOT
   ./scripts/collect-control-plane.sh "$CASE_ROOT/01-closed-control"
   ./scripts/make-probe-config.sh "$CASE_ROOT/probe-config.json"
   export PROBE_CONFIG="$CASE_ROOT/probe-config.json"
   ```

   Expect: Correct subscription; collector summary with no failed reads; a six-field probe config (`edge_fqdn`, `origin_fqdn`, `gateway_public_ip`, `backend_fqdn`, `frontdoor_id`, `operator_cidr`). A failed read is a stop.

## Activity 3: Publish the reviewed fixture

**Goal.** Open the SCM gate for one upload of the exact reviewed bytes, then close it again.

**Exam skill.** Separate deployment accepted from backend ready, and know that SCM has its own restriction list.

1. **Publish the reviewed fixture through SCM**: With edge and diagnostic ingress closed, set `fixture_publish_enabled=true`, check the SCM C/32 rule, then upload the exact reviewed bytes. Afterwards set `fixture_ready=true` and `fixture_publish_enabled=false`.

   ```bash
   REVIEWED_ZIP='/absolute/path/to/reviewed/origin.zip'
   REVIEWED_SHA256='REPLACE_WITH_INDEPENDENTLY_REVIEWED_64_HEX_SHA256'
   ./scripts/deploy-origin.sh --confirm-synthetic-origin-upload \
     "$REVIEWED_ZIP" "$REVIEWED_SHA256"
   ```

   Expect: The script verifies the hash and structure, uploads a private snapshot via Entra-authenticated CLI and restarts the app. An accepted deployment is **not** backend readiness. A direct request from C to the main site should still be denied.

## Activity 4: Point DNS at the gateway and prove backend health

**Goal.** Make the origin hostname resolve to the gateway's public IP and prove the gateway can reach a healthy backend.

**Exam skill.** A healthy backend probe says nothing yet about Front Door, leg 2 certificates or FDID.

1. **Point DNS at P and prove backend health**: Through the zone owner, point Horigin's A record at the actual P and verify it; set `origin_dns_verified=true`. Then set `backend_access_enabled=true` (main site allows P/32) and check the gateway's probe.

   ```bash
   load_context
   az network application-gateway show-backend-health \
     --subscription "$SUBSCRIPTION_ID" --ids "$(read_output gateway_id)" \
     --query '{backendAddressPools:backendAddressPools}' --output json
   ./scripts/collect-control-plane.sh "$CASE_ROOT/02-backend-ready-control"
   ```

   Expect: Backend `Healthy` for `/health` with Host Hbackend. Only then set `backend_health_verified=true`. This says nothing yet about Front Door, certificates on leg 2 or FDID.

## Activity 5: The FDID diagnostic window

**Goal.** Open a supervised window for the operator's single address, test the six FDID cases and close it again.

**Exam skill.** Explain why a forged FDID sent to a network-blocked listener cannot test the FDID rules, and why the window must close before the edge opens.

1. **Define the case wrapper**: This shell function records each probe's exit code without letting a negative case abort the run, and refuses to reuse a label.

   ```bash
   export LOCAL_ADDRESS='0.0.0.0'
   export PUBLIC_CA_PEM='/etc/ssl/certs/ca-certificates.crt'
   run_case() {
     local label=$1 mode=$2 rc
     shift 2
     [[ "$label" =~ ^[a-z0-9-]+$ ]] || return 2
     [[ ! -e "$CASE_ROOT/$label" && ! -L "$CASE_ROOT/$label" \
        && ! -e "$CASE_ROOT/$label.exit" && ! -L "$CASE_ROOT/$label.exit" ]] || return 2
     if ./scripts/waf-probe --config "$PROBE_CONFIG" --mode "$mode" \
          --local-address "$LOCAL_ADDRESS" --ca-file "$PUBLIC_CA_PEM" \
          --out "$CASE_ROOT/$label" "$@"; then
       rc=0
     else
       rc=$?
     fi
     (set -C; printf '%s\n' "$rc" > "$CASE_ROOT/$label.exit") || return 2
     printf '%s recorded exit %s; inspect result and service evidence.\n' "$label" "$rc"
   }
   ```

   Expect: `0.0.0.0` lets the OS choose the interface; it is **not** evidence of C. Each case writes `attempt.json` (before connect) and `result.json`.

2. **Diagnostic window: one request, close, review**: After explicit approval set `diagnostic_ingress_authorized=true` and `fdid_diagnostic_ingress_enabled=true` (edge and SCM off; preferably `gateway_ingress_enabled=false`). Send one correct-FDID request, then close the window immediately and prove it is closed.

   ```bash
   ./scripts/collect-control-plane.sh "$CASE_ROOT/03-diagnostic-open-control"
   run_case 04-first-diagnostic fdid-correct --confirm-diagnostic-ingress
   # set fdid_diagnostic_ingress_enabled=false, then:
   ./scripts/collect-control-plane.sh "$CASE_ROOT/03b-first-diagnostic-closed-control"
   run_case 04b-first-diagnostic-closed direct-gateway
   ```

   Expect: First case returns the fixture; after closure, `direct-gateway` fails at the network (exit 3). `--confirm-diagnostic-ingress` records intent only; it does not open anything.

3. **Diagnostic window: the full FDID matrix**: Only after review and a separate approval, reopen the same gate, recheck backend health and run the six header cases.

   ```bash
   ./scripts/collect-control-plane.sh "$CASE_ROOT/03c-diagnostic-reopened-control"
   run_case 04-fdid-correct fdid-correct --confirm-diagnostic-ingress
   run_case 05-fdid-missing fdid-missing --confirm-diagnostic-ingress
   run_case 06-fdid-wrong fdid-wrong --confirm-diagnostic-ingress
   run_case 07-fdid-mixed-duplicate fdid-duplicate --confirm-diagnostic-ingress
   run_case 08-fdid-valid-duplicate fdid-duplicate-valid --confirm-diagnostic-ingress
   run_case 09-fdid-case fdid-case --confirm-diagnostic-ingress
   ```

   Expect: Correct and case variant → fixture. Missing, wrong and both duplicates → no fixture, each with its named regional rule. Any accepted duplicate → **stop**, keep the edge closed.

4. **Close the window and verify both bypass locks**

   ```bash
   # set fdid_diagnostic_ingress_enabled=false, then:
   ./scripts/collect-control-plane.sh "$CASE_ROOT/10-diagnostic-closed-control"
   run_case 11-direct-origin-closed direct-gateway
   run_case 12-direct-backend-closed direct-backend
   ```

   Expect: Direct gateway: network failure (NSG). Direct backend: App Service 403 (P/32 only). Only after reviewing all of this set `fdid_negative_cases_verified=true`.

## Activity 6: Enable the Front Door origin and publish the edge

**Goal.** Open the origin, publish the route for one controlled request, then run the full test matrix.

**Exam skill.** Tell an edge block, a regional block, a network drop and an App Service denial apart using named rules and logs.

1. **Enable the Front Door origin**: Set `gateway_ingress_enabled=true`: NSG rule 100 allows `AzureFrontDoor.Backend` and the origin is enabled. Diagnostic and SCM stay closed.

   ```bash
   ./scripts/collect-control-plane.sh "$CASE_ROOT/13-origin-ready-control"
   ```

   Expect: Origin configuration correct; any available probe evidence healthy. With the route still disabled Front Door may report little; absence of data stays *unverified*.

2. **Publish the edge: one request, close, review**: Set `edge_route_enabled=true` after approval, send one positive request, then withdraw the route and review the first complete chain with it closed.

   ```bash
   ./scripts/collect-control-plane.sh "$CASE_ROOT/14-edge-published-control"
   run_case 15-first-edge-positive edge-positive
   # set edge_route_enabled=false, then:
   ./scripts/collect-control-plane.sh "$CASE_ROOT/14b-first-edge-closed-control"
   run_case 15b-first-edge-closed edge-positive
   ```

   Expect: First request: fixture JSON with the case UUID, plus edge, gateway and backend rows. After withdrawal: no fixture.

3. **Reopen the edge and run the matrix**

   ```bash
   ./scripts/collect-control-plane.sh "$CASE_ROOT/14c-edge-reopened-control"
   run_case 15-edge-positive edge-positive
   run_case 16-edge-marker edge-block
   run_case 17-regional-marker regional-block
   run_case 18-edge-positive-after-negatives edge-positive
   run_case 19-direct-origin-baseline direct-gateway
   run_case 20-direct-backend-baseline direct-backend
   ```

   Expect: Fixture; edge 403 `BlockEdgeMarker`; gateway 403 `BlockRegionalMarker`; fixture again; network failure; App Service 403.

## Activity 7: Withdraw, close and clean up

**Goal.** Remove access in reverse order, restore DNS and delete only what the lab owns.

**Exam skill.** Know that closing gates does not stop billing, that `deploy_lab=false` destroys the module, and that a closed route is verified with a fresh request.

1. **Stop clients and preserve evidence**: Confirm no probe or upload is running. Keep case IDs, time windows, policy revisions and the reviewed ZIP hash. A client timeout is not closure.

2. **Withdraw the edge before removing anything**

   ```bash
   # set edge_route_enabled=false, then:
   ./scripts/collect-control-plane.sh "$CASE_ROOT/21-edge-withdrawn-control"
   run_case 22-edge-after-withdrawal edge-positive
   run_case 23-direct-origin-after-withdrawal direct-gateway
   ```

   Expect: No fixture on either path. A fixture response here is an unresolved closure problem (global propagation is not instant), not a pass. Continue with clean-up.

3. **Close both gateway ingress paths and SCM**: Set `gateway_ingress_enabled=false`, `fdid_diagnostic_ingress_enabled=false` and `fixture_publish_enabled=false`. Rules 100 and 110 go back to Deny and the origin is disabled. Verify `direct-gateway` fails. Keep the GatewayManager and AzureLoadBalancer rules.

4. **Close backend access**: Set `backend_access_enabled=false` **and** `backend_health_verified=false` together (validation rejects the change if gateway ingress or the edge route is still on). Verify `direct-backend` still fails. An unhealthy probe is the expected side effect.

5. **Clear stale attestations**: Reset `fixture_ready`, `origin_dns_verified`, `fdid_negative_cases_verified` and `diagnostic_ingress_authorized`. Keep `deploy_lab=true` and `certificate_access_confirmed=true` while resources still exist (validation requires the pair).

6. **Restore DNS and review access**: Remove or restore only the Horigin record you changed. Keep the Key Vault, certificate, identity and zone: they are external and may serve others. Revoke only this lab's certificate access, with the owner's approval.

7. **Remove the owned infrastructure**: Under a separately reviewed destroy plan (setting `deploy_lab=false` destroys the module). Check gateway, public IP, Front Door profile, App Service and plan, and the workspace separately.

8. **Verify the final state**: No endpoint still returns the fixture, SCM is unreachable, no DNS record points at a released public IP, and the resources are gone. If deletion fails, report what still exists and bills; never widen access to finish clean-up.
