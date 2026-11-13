# Lab guide: Virtual WAN Internet egress through a security partner provider

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied, and no Zscaler tenant exists for it: every command is a procedure for a future, approved run. The hub VPN gateway, the Bastion hosts and the provider licence bill while they exist.

## Activity 1: Prepare the inputs and run the local checks

**Goal.** Fill in the example inputs with every gate false, and run every check that needs no Azure resources.

**Exam skill.** Know that the safe starting state has all gates false, that local and mocked tests say nothing about Azure, and that no secret belongs in the lab.

1. **Copy the example inputs**: The example tfvars deliberately contains invalid placeholders and every gate false. Edit the subscription UUID, the region and the image version, and keep every gate false.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   : "${PUBLIC_KEY_FILE:?Set approved existing PUBLIC key file}"
   export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
   ```

   Expect: Only the public key is passed, through the environment. Nothing secret is written to a file.

2. **Run the offline checks**: The local suite checks Python and Bash syntax, a static source contract, loopback tests of the fixture and probe, and operator tests with a fake command line tool. Terraform then formats, initialises and validates, and the mocked plan tests run.

   ```bash
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass. The Terraform tests are mock-provider plans. `init` may download provider code. None of these prove that Azure accepts the schema.

3. **Confirm the subscription and the extensions**: The helpers never install extensions and never sign in, so the approved Azure CLI extensions must already exist.

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   az account show --subscription "$SUBSCRIPTION_ID"
   az extension show --name virtual-wan
   az extension show --name bastion
   ```

   Expect: The approved tenant and subscription, and the installed versions of both extensions.

## Activity 2: Review each stage's plan and apply the first stage

**Goal.** Preview what Terraform will create, check it against the design, and only after a separate approval build the first stage.

**Exam skill.** Read a plan for the design's key facts: no public IP on the app NIC, no SPP yet, test rules still Deny, and a cost you accept.

1. **Plan stage one**: Use a new private directory per stage. Review replacements, deletions, gateway capacity, public mappings and NSG actions before a separate approval to apply.

   ```bash
   set -euo pipefail
   umask 077
   : "${APPROVED_INPUTS:?Set the reviewed private input file for this stage}"
   test -f "$APPROVED_INPUTS"
   PLAN_DIR=$(mktemp -d "$PWD/spp-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/review.tfplan"
   terraform show -no-color "$PLAN_DIR/review.tfplan" > "$PLAN_DIR/review.txt"
   ```

   Expect: First stage: only `deploy_lab` and `image_prerequisites_confirmed` true. Hub, gateway, management and three VMs; no SPP, no source default, test NSGs Deny.

2. **Review the plan against the design**: Read `review.txt` before anyone approves it. Check the subscription and region, that only dedicated lab resources appear, that the app NIC has no public IP, that there are four Standard public IPs (two origin, two Bastion), that every test NSG rule 100 is Deny, that there is no SPP and no source default, and that you accept the gateway and hub cost.

   Expect: A reviewed plan, with every replacement and deletion explained. Stop here unless deployment is approved.

3. **Apply the reviewed plan, only after approval**: The original package embeds no apply command. This is the standard form for a saved plan. Gateway deployment can take a long time, and a finished apply is not tunnel readiness.

   ```bash
   terraform apply "$PLAN_DIR/review.tfplan"
   terraform output
   ```

   Expect: Hub, gateway, management and three VMs exist. SPP, source default and test paths are still off, and `test_nsg_action` is Deny.

## Activity 3: Associate the partner, onboard externally and capture a closed snapshot

**Goal.** Create the Azure side of the association, let the provider build its side through its own workflow, and record a read-only snapshot while everything is still closed.

**Exam skill.** Explain why an SPP in the Succeeded state with connectionStatus Unknown is not an integration, and what evidence the onboarding really needs.

1. **Load the scoped context**: This guard checks the declared Terraform outputs against the expected resource IDs. It is an identity check, not proof of authorisation or reachability.

   ```bash
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   source ./scripts/common.sh
   load_context
   require_extensions virtual-wan bastion
   ```

   Expect: `RG`, `HUB`, `HUB_ID` and `GATEWAY_ID` are set. A foreign or malformed output stops the script before any Azure read.

2. **Plan and apply the SPP association**: Supply the reviewed non-secret profile, then plan a stage with `enable_spp=true` and apply it only after approval. Read the SPP state with a limited projection.

   ```bash
   : "${APPROVED_PROFILE_FILE:?Set reviewed NONSECRET provider profile JSON}"
   export TF_VAR_provider_profile="$(cat "$APPROVED_PROFILE_FILE")"
   # after the approved apply:
   SPP_ID=$(read_output spp_id)
   az resource show --subscription "$SUBSCRIPTION_ID" --ids "$SPP_ID" \
     --api-version 2025-07-01 \
     --query '{id:id,type:type,location:location,provider:properties.securityProviderName,hub:properties.virtualHub.id,provisioning:properties.provisioningState,connection:properties.connectionStatus}' -o json
   ```

   Expect: provider `ZScaler`, hub = `spp-hub`. `Succeeded` with `connectionStatus` Unknown is normal at this point and is **not** an integration.

3. **Onboard externally**: Complete the ZIA licence, the authorisation, the integration, the tunnels and the location in the supported workflow. Record the provider-created site and connection IDs, and the tunnel inventory and state on both the Azure and the ZIA side. Do not create duplicate connections and do not inject a 0.0.0.0/0 by hand.

   Expect: Both-side tunnel evidence from the responsible operators. Set `provider_onboarding_verified` and `tunnels_verified` only from that evidence.

4. **Capture a closed snapshot**: Complete the ZIA licence, authorisation, integration, tunnels and location in the supported workflow. Then collect read-only evidence into a new path. The helper collects scoped read-only metadata into a new directory.

   ```bash
   EVIDENCE_PARENT=$(mktemp -d "$PWD/spp-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/onboarding-closed"
   ```

   Expect: `summary.txt` with `vpn_connection_read_opted_in=false` and route/tunnel/policy verification `NOT_PERFORMED`. Exit 0 with the default VPN skip is **not** tunnel verification; get both-side tunnel evidence from the responsible operators.

## Activity 4: Route, opt in and verify the routes

**Goal.** Let the external owner enable protected hub routing, opt the app connection in through Terraform, and prove with effective routes that the protected default is selected.

**Exam skill.** Prove steering with effective routes, and know who owns each half of the default route: the hub side is external, the VNet side is the connection opt-in.

1. **Enable protected hub routing through its owner**: The external owner (Firewall Manager or the supported partner workflow) enables it while the NSG envelopes stay closed. Terraform creates no routing intent and no hand-made 0.0.0.0/0.

   Expect: Written evidence of who changed what and when. Set `provider_routing_configured` only from that evidence.

2. **Plan and apply the opt-in**: Set the three external gates from real evidence, then plan `enable_source_default=true` and keep `test_paths_enabled=false`. A validation rule refuses the opt-in unless the earlier gates are true.

   ```bash
   set -euo pipefail
   umask 077
   : "${APPROVED_INPUTS:?Set the reviewed private input file for this stage}"
   test -f "$APPROVED_INPUTS"
   PLAN_DIR=$(mktemp -d "$PWD/spp-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/review.tfplan"
   terraform show -no-color "$PLAN_DIR/review.tfplan" > "$PLAN_DIR/review.txt"
   ```

   Expect: The plan changes only `internet_security_enabled` on `connect-app`. Apply it only after approval.

3. **Re-collect and read the routes**: Replace the hub variable names with the ones the scripts set.

   ```bash
   DEFAULT_TABLE_ID=$(read_output hub_default_route_table_id)
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/source-default-nsg-closed"
   az network vhub connection show --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vhub-name "$HUB" --name connect-app -o json
   az network vhub get-effective-routes --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$HUB" \
     --resource-type RouteTable --resource-id "$DEFAULT_TABLE_ID" -o json
   az network nic show-effective-route-table --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name app-nic -o json
   ```

   Expect: `app-nic` selects the hub-learned 0/0 for D1 and D2, with no more-specific override; the 10.40.0.0/16 peering route is still there and Bastion SSH to A still works.

## Activity 5: Prove both origins and build the runtime config

**Goal.** Open each origin through its own Bastion, run the readiness check, and give the app VM its public runtime file once the complete egress pool E is known.

**Exam skill.** Separate management from the egress path, and know that readiness is a local check and never end-to-end proof.

1. **Open an origin through origin-bastion**: Use `app-bastion` for the app VM and `origin-bastion` for the origins. Keep host-key checking on, run it from your own computer, and never move a Bastion into the protected VNet or put a UDR on `AzureBastionSubnet`.

   ```bash
   require_extensions bastion
   : "${SSH_PRIVATE_KEY_FILE:?Set existing approved local SSH key path}"
   az_read network bastion ssh -g "$RG" -n origin-bastion \
     --target-resource-id "$(read_map_output vm_ids origin1)" --auth-type ssh-key \
     --username "$(read_output admin_username)" --ssh-key "$SSH_PRIVATE_KEY_FILE"
   ```

   Expect: A shell on origin1. Repeat for origin2 with `vm_ids origin2`.

2. **Run the readiness check on each origin**: Run it on origin1 and then on origin2.

   ```bash
   umask 077
   READY_DIR=$(mktemp -d "$HOME/spp-ready-XXXXXXXX")
   spp-ready > "$READY_DIR/readiness.json"
   ss -ltn > "$READY_DIR/listeners.txt"
   
   ```

   Expect: Each origin reports `LOCAL_FIXTURES_READY` with one listener on TCP 80. Empty E is allowed here and reported as `pool_not_ready`.

3. **Build the public runtime file on your workstation**: This reads only declared Terraform outputs, needs the complete reviewed E pool, and writes a new file with mode 0600.

   ```bash
   export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
   umask 077
   RUNTIME_DIR=$(mktemp -d "$PWD/spp-runtime-XXXXXXXX")
   ./scripts/make-runtime-config.sh app "$RUNTIME_DIR/app.json"
   sha256sum "$RUNTIME_DIR/app.json"
   ```

   Expect: A JSON file with five fields: role, private_ip, app_ip, origins, egress_public_ips. Review them before copying.

4. **Copy it to A and check readiness**: Copy only that public JSON through the already approved Bastion-native transfer path and compare the hash. Then on A:

   ```bash
   : "${PUBLIC_RUNTIME_CONFIG:?Set reviewed public JSON on this VM}"
   export SPP_LAB_CONFIG="$PUBLIC_RUNTIME_CONFIG"
   spp-ready
   ```

   Expect: `LOCAL_CLIENT_READY` on A. A change in D or E invalidates earlier evidence, so close the tests and review again.

## Activity 6: Activate the Block baseline, open the envelopes and run the closed test

**Goal.** Start from a known closed policy, open exactly the test paths, and show that D1 is blocked by a named ZIA rule.

**Exam skill.** Explain why a closed baseline comes first, and what proof a Block needs besides a timeout.

1. **Activate Block for D1 and D2 in ZIA**: In ZIA, create or confirm the literal-IP custom categories and activate Block for both in the exact lab location and client context. Confirm that no exception or broad Allow defeats it, and record the activated revision.

   Expect: A recorded activation time and revision. A saved draft is not an activated policy.

2. **Open the test envelopes**: Set `protected_routes_verified`, `fixtures_ready` and `provider_block_policy_verified` from real evidence, then plan and apply `test_paths_enabled=true`. The validation refuses it unless the earlier gates are true and E is non-empty. Verify rule 100 on all three NICs.

   ```bash
   az network nic list-effective-nsg --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name app-nic -o json
   ```

   Expect: Rule 100 `test-web-egress` is Allow on app-nsg. Check both origin NICs the same way, otherwise a timeout cannot be blamed on ZIA.

3. **Run the closed baseline on A**: From a shell on A, with the runtime file in place.

   ```bash
   export SPP_LAB_CONFIG
   spp-ready
   APP_EVIDENCE=$(mktemp -d "$HOME/spp-app-XXXXXXXX")
   spp-probe closed --out "$APP_EVIDENCE/primary-block-baseline"
   ```

   Expect: A non-fixture response, reset or timeout **plus** the named D1 Block in ZIA logs.

## Activity 7: Activate D1 Allow only: the positive and alternate tests

**Goal.** Change exactly one thing, the D1 rule, from Block to Allow, then run the positive case and the alternate (negative) case.

**Exam skill.** Prove an Allow with a joined set of evidence, and a Block with a named rule, never with HTTP 200 or a timeout alone.

1. **Activate D1 Allow only**: Through the supported ZIA workflow, activate Allow for D1, keep D2 at Block and keep the Azure path unchanged. Record the activated revision before you test.

   Expect: The only provider change since the baseline is D1 from Block to Allow.

2. **Run the positive and alternate cases on A**: Each run writes a new private evidence directory.

   ```bash
   spp-probe positive --out "$APP_EVIDENCE/primary-allow"
   spp-probe alternate --out "$APP_EVIDENCE/healthy-alternate-block"
   ```

   Expect: Positive: `FIXTURE_RESPONSE` from origin1 joined to ZIA and the origin journal. Alternate: named D2 Block with no need for an origin2 record.

3. **Join the evidence**: Read the origin journal for the exact test window, then join the case path, B1:80 and E:q with the client's A:a to D1:80 and the ZIA transaction.

   ```bash
   # on origin1, in its verified session
   : "${START_UTC:?Set exact recorded UTC start}"
   : "${END_UTC:?Set exact recorded UTC end}"
   sudo journalctl --utc --since "$START_UTC" --until "$END_UTC" \
     -u azure-spp-fixture.service --no-pager -o cat
   ```

   Expect: A fixture frame with the case id and the peer E:q for D1. No origin2 record is needed for the D2 Block.

## Activity 8: Measure closure, then prove a fresh Block

**Goal.** See what happens to an existing session when D1 returns to Block, and prove that a new request is blocked.

**Exam skill.** Do not assume that a policy change ends open sessions: measure the old session and the fresh request as two separate questions.

1. **Run the stream while the policy closes**: Start the stream, then activate the D1 Block in ZIA while it runs, and record the activation time.

   ```bash
   spp-probe stream --duration 180 --out "$APP_EVIDENCE/stream-policy-close"
   ```

   Expect: A frame timeline. Compare it with the activation interval. If the activation takes longer than the stream, the result is INCONCLUSIVE.

2. **Prove a fresh Block and snapshot**: A fresh request after the activation answers a different question than the old stream.

   ```bash
   spp-probe closed --out "$APP_EVIDENCE/primary-block-restored"
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/provider-block-restored"
   ```

   Expect: A fresh named Block for D1, and a new snapshot of the control plane.

## Activity 9: Tear down in ownership order

**Goal.** Close the policy, isolate the endpoints, undo routing through each owner, unlink the partner, and only then remove the Azure resources.

**Exam skill.** Know why the gateway must not be deleted before the partner is unlinked, and that deallocating or closing rules does not stop billing.

1. **Close policy and stop clients**: Activate the D1 Block, prove a fresh Block and record the old-session outcome. A saved draft or a closed console is not closure.

2. **Stop both origin services**: On origin1 and then origin2, separately, after confirming hostname and private address. The service is not restarted automatically.

   ```bash
   set -euo pipefail
   sudo systemctl stop azure-spp-fixture.service
   STATE=$(sudo systemctl show azure-spp-fixture.service --property=ActiveState --value)
   if [ "$STATE" != inactive ]; then
     printf 'STOP: expected inactive origin service, observed %s\n' "$STATE" >&2
     exit 1
   fi
   SOCKETS=$(ss -H -ltn '( sport = :80 )')
   if [ -n "$SOCKETS" ]; then
     printf 'STOP: TCP80 still listens on this origin\n%s\n' "$SOCKETS" >&2
     exit 1
   fi
   ```

   Expect: Both units inactive and nothing listening on 80. Any error stops the rest of the tear-down.

3. **Close the envelopes and snapshot**: Apply `test_paths_enabled=false` while everything else still exists, verify rule 100 is Deny on all three NSGs, then collect.

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/pre-removal-isolated"
   ```

   Expect: Deny on `test-web-egress` and both `test-web-ingress`. NSG changes do not end existing flows by themselves.

4. **Undo routing through each owner**: Remove the app opt-in through Terraform and restore or remove the hub's protected routing through its external owner. Capture the final routes.

5. **Unlink the partner**: Use the supported workflow to remove the location, integration and provider-created VPN sites and connections. **Do not delete the gateway first**: it is the transport dependency. Deleting the SPP does not cancel a licence, remove the service principal's access or erase external tunnels.

6. **Remove owned Azure resources and review access**: Review a plan that removes the SPP, gateway, hub, WAN, connection, peerings, three VNets, three VMs and disks, two Bastions and four public IPs. Keep the existing image and keys. Respect the resource-group deletion safeguard. Credential, grant and licence clean-up is a separate approval. The original package embeds no destroy command; this is the standard Terraform form for reviewing it.

   ```bash
   terraform plan -destroy -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/destroy.tfplan"
   terraform show -no-color "$PLAN_DIR/destroy.tfplan"
   ```

   Expect: A reviewed plan that removes only owned resources. Apply it only after approval, and check the residual objects through supported reads.
