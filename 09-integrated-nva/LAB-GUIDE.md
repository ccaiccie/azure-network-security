# Lab guide: partner NVA integrated into a Virtual WAN hub (Internet intent)

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied, and no vendor was selected: every command is a procedure for a future, separately approved run. The lab ships no apply or destroy command. The virtual hub, the appliance, the Bastions and the vendor licence bill while they exist.

## Activity 1: Prepare inputs and run the local checks

**Goal.** Run every check that needs no Azure deployment and no vendor.

**Exam skill.** Know that the checks are offline and mock-provider plans, and that all eight gates stay false.

1. **Prepare inputs and run local checks**: From the `lab` folder, copy the example inputs (all gates stay false) and supply an existing public key from the environment. The placeholders intentionally fail validation until you replace them.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   : "${PUBLIC_KEY_FILE:?Set approved existing PUBLIC key file}"
   export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass. The tests are mock-provider plans, not Azure tests. `init` may download the provider.

## Activity 2: Plan the first stage, apply it after approval, check the scope

**Goal.** Review what Terraform will create, build only the owned infrastructure after approval, and confirm the scope.

**Exam skill.** Read a plan for the design's key facts: no VM public IP, no source UDR, two origin-side exposures only, NSGs closed.

1. **Plan each stage for review**: Put the reviewed inputs for one stage in a private file. The first stage sets `deploy_lab` and `image_prerequisites_confirmed` true, everything else false, `vendor_profile = null` and an empty E pool.

   ```bash
   set -euo pipefail
   umask 077
   : "${APPROVED_INPUTS:?Set the reviewed private input file for this exact stage}"
   test -f "$APPROVED_INPUTS"
   PLAN_DIR=$(mktemp -d "$PWD/partner-plan-XXXXXXXX")
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/review.tfplan"
   terraform show -no-color "$PLAN_DIR/review.tfplan" > "$PLAN_DIR/review.txt"
   ```

   Expect: A plan you review for replacements, deletions, public mappings and NSG actions. The lab embeds **no apply or destroy command**: applying is a separate, approved operator action.

2. **Apply the reviewed plan only after approval**: The original lab embeds no apply command. After the plan review and a separate approval, apply the saved plan with the standard command. The first stage creates the owned infrastructure with both NSG envelopes still closed and no routing intent.

   ```bash
   terraform apply "$PLAN_DIR/review.tfplan"
   ```

   Expect: Terraform reports the owned resources created. Applied means provisioned, not working: no egress is proven yet, and no vendor appliance exists in the hub.

3. **Check scope after the first deployment**: Read the outputs and let the lab's guard confirm the subscription, the six core network IDs, both VM IDs and the NIC map. The guard is a long Python block in the runbook; its essence is shown here.

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   : "${SUBSCRIPTION_ID:?Set the expected approved subscription UUID}"
   export SUBSCRIPTION_ID
   TF_OUTPUTS=$(terraform output -json)
   export TF_OUTPUTS
   # ... python3 scope guard from the runbook ...
   az account show --subscription "$SUBSCRIPTION_ID" \
     --query '{id:id,tenant:tenantId,name:name}' -o json
   az extension show --name virtual-wan --query version -o tsv
   az extension show --name bastion --query version -o tsv
   ```

   Expect: `Local scope matched. No Azure route, vendor identity or policy verified by this check.` and the expected tenant and subscription.

## Activity 3: Onboard N with the vendor and record its identity

**Goal.** Install the appliance through the vendor, outside Terraform, and read its projected identity.

**Exam skill.** Know that a resource ID proves a string, not a licence, a policy or a log, and that the lab is BLOCKED without a supported vendor.

1. **Onboard N with the vendor, then record the profile**: With the NSGs still closed, use the vendor's official workflow to install N into this exact hub, license it and configure management, NAT and logging. This is outside Terraform. Then fill the non-secret profile (`profiles/vendor-profile.example.json`) and read N's projected identity.

   ```bash
   : "${APPROVED_PROFILE_FILE:?Set reviewed nonsecret vendor profile JSON}"
   export TF_VAR_vendor_profile="$(cat "$APPROVED_PROFILE_FILE")"
   # after a reviewed stage update:
   NVA_ID=$(read_output nva_resource_id)
   IDENTITY_DIR=$(mktemp -d "$PWD/partner-identity-XXXXXXXX")
   az resource show --subscription "$SUBSCRIPTION_ID" --ids "$NVA_ID" \
     --api-version 2025-05-01 \
     --query '{id:id,type:type,location:location,state:properties.provisioningState,hub:properties.virtualHub.id,sku:properties.nvaSku,nics:properties.virtualApplianceNics[].{name:name,type:nicType,instance:instanceName,private_ip:privateIpAddress,public_ip:publicIpAddress}}' \
     -o json > "$IDENTITY_DIR/nva-projected.json"
   ```

   Expect: N's linked hub equals H, the managed group and plan match the profile. If no supported vendor can be onboarded, stop: the experiment is **BLOCKED**.

## Activity 4: Enable Internet intent with the NSGs closed

**Goal.** Turn on routing intent and read the decision points in Azure.

**Exam skill.** Prove steering with the NIC's effective routes and the hub's defaultRouteTable, not with the connection setting alone.

1. **Enable Internet intent with the envelopes closed**: Apply the reviewed stage with `vendor_ready` and `enable_internet_intent` true and `test_paths_enabled` still false, then collect a fresh snapshot and read the decision points.

   ```bash
   EVIDENCE_PARENT=$(mktemp -d "$PWD/partner-review-XXXXXXXX")
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/intent-nsg-closed"
   az network vhub routing-intent list --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --vhub "$HUB_NAME" -o json
   az network vhub get-effective-routes --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name "$HUB_NAME" \
     --resource-type RouteTable --resource-id "$DEFAULT_TABLE_ID" -o json
   az network nic show-effective-route-table --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name app-nic -o json
   ```

   Expect: One `connect-app` with internet security true; `InternetTrafficPolicy` → N; A's 0.0.0.0/0 learned from the hub; `10.40.0.0/16` still via peering; no UDR, NAT Gateway or public IP on A.

## Activity 5: Prove origin health and give A its public runtime file

**Goal.** Reach both VMs through their Bastions, prove the listeners locally and hand A the reviewed runtime values.

**Exam skill.** Separate local readiness from a public-path test, and know why E is not guessed.

1. **Prove origin health locally**: SSH to B through `origin-bastion` with an existing key, then check both listeners. A is reached the same way through `app-bastion`.

   ```bash
   : "${SSH_PRIVATE_KEY_PATH:?Set the existing local key path, never its contents}"
   az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --name origin-bastion \
     --target-resource-id "$ORIGIN_VM_ID" --auth-type ssh-key \
     --username "$ADMIN" --ssh-key "$SSH_PRIVATE_KEY_PATH"
   # on B:
   partner-ready
   sudo systemctl status --no-pager azure-partner-fixture@8080.service \
     azure-partner-fixture@8081.service
   ```

   Expect: `LOCAL_FIXTURES_READY` with marker `azure-partner-origin-v1` on B; `LOCAL_CLIENT_READY` on A. Local only: no public route is proved.

2. **Give A the reviewed public runtime file**: Build the six-field runtime JSON locally from outputs (it needs the real D and a complete E pool), copy it to A through an approved Bastion transfer, then select it on A.

   ```bash
   RUNTIME_DIR=$(mktemp -d "$PWD/partner-runtime-XXXXXXXX")
   ./scripts/make-runtime-config.sh app "$RUNTIME_DIR/app-runtime.json"
   sha256sum "$RUNTIME_DIR/app-runtime.json"
   # on A, after the approved copy:
   : "${PARTNER_LAB_CONFIG:?Set the path to the reviewed copied app-runtime.json}"
   export PARTNER_LAB_CONFIG
   sha256sum "$PARTNER_LAB_CONFIG"
   partner-ready
   APP_EVIDENCE=$(mktemp -d "$HOME/partner-app-XXXXXXXX")
   ```

   Expect: Matching hashes. An E-only change uses this file plus a reviewed NSG change, never a VM replacement.

## Activity 6: Open the envelopes and run the named Deny baseline

**Goal.** Let the vendor's named Deny be the only thing that can stop the primary flow.

**Exam skill.** Attribute a failure to the vendor only when both envelopes are open and the log names the Deny for the attempted tuple.

1. **Open the envelopes for the named Deny baseline**: With both vendor rules installed as Deny, apply the stage that sets `fixtures_ready`, `internet_routes_verified`, `vendor_deny_policy_verified` and `test_paths_enabled` true. Then snapshot and probe from A.

   ```bash
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/vendor-deny-baseline"
   # on A:
   partner-probe closed --out "$APP_EVIDENCE/primary-deny-baseline"
   ```

   Expect: Failure matched to the vendor's named primary Deny for the exact attempted tuple and UTC.

## Activity 7: Vendor installs the Allow: positive test and healthy alternate

**Goal.** See one flow allowed and translated, and one controlled negative on a healthy listener.

**Exam skill.** Join the original tuple, the vendor log and the origin record; use FAIL, BLOCKED and INCONCLUSIVE correctly.

1. **Vendor installs the primary Allow; run the positive and the alternate**: Change **only** the 8080 rule to Allow through the vendor's workflow and confirm the installed revision. Nothing in Azure changes.

   ```bash
   # on A:
   partner-probe positive --out "$APP_EVIDENCE/primary-allow"
   partner-probe alternate --out "$APP_EVIDENCE/healthy-alternate-deny"
   ```

   Expect: Positive: response from B:8080 with peer E:q from the approved pool, plus vendor Allow and mapping. Alternate: named 8081 Deny.

## Activity 8: Measure policy closure

**Goal.** Observe what happens to an existing stream and a fresh connection when the vendor closes the rule.

**Exam skill.** Never import another product's session behaviour; measure the vendor you have.

1. **Measure closure**: Start one finite stream, wait for frames, then have the vendor install the primary Deny. Afterwards test a fresh connection and take a closure snapshot.

   ```bash
   # on A:
   partner-probe stream --duration 180 --out "$APP_EVIDENCE/stream-policy-close"
   # ... vendor installs primary Deny ...
   partner-probe closed --out "$APP_EVIDENCE/primary-deny-restored"
   # operator shell:
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/vendor-deny-restored"
   ```

   Expect: The stream outcome is product-specific (5 s socket timeout, duration + 10 s cap). The fresh connection must hit the named Deny.

## Activity 9: Isolate, then tear down in order

**Goal.** Remove everything in the order that ownership requires and prove nothing is left running or billing.

**Exam skill.** Know that Azure refuses to delete an NVA a routing policy references, and that a blind destroy does not know the vendor's order.

1. **Stop clients and install the vendor Deny**: Let every bounded probe finish. Then have the vendor install the primary Deny through its supported workflow and record the actual installed action, the fresh-flow result and the session outcome.

   Expect: A recorded installed revision, a fresh matched Deny and a note on what happened to any old session.

2. **Stop both origin fixtures**: Stop exactly the two units on B and check that both are `inactive` and nothing listens on 8080 or 8081. Failed checks stop the teardown.

   ```bash
   sudo systemctl stop azure-partner-fixture@8080.service azure-partner-fixture@8081.service
   ss -H -ltn '( sport = :8080 or sport = :8081 )'
   ```

   Expect: Both units `inactive` and no listener output.

3. **Close both NSG envelopes**: Plan and, after approval, apply the stage with `test_paths_enabled = false` while infrastructure and intent remain. NSGs are stateful: a rule edit alone does not prove earlier sessions ended.

   ```bash
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/close-nsg.tfplan"
   ./scripts/collect-control-plane.sh "$EVIDENCE_PARENT/pre-teardown-isolated"
   ```

   Expect: The plan changes only the two priority-100 rules to Deny. The snapshot shows both effective rules Deny.

4. **Remove the routing intent**: Only after isolation, plan and apply a reviewed stage with `enable_internet_intent = false`. Removing intent changes propagation and does not restore an earlier routing design, so it is not a safe default-withdrawal test.

   ```bash
   terraform plan -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/remove-intent.tfplan"
   ```

   Expect: The plan removes `internet-inspection` only. Azure refuses to delete the NVA while a routing policy still references it.

5. **Uninstall N through its owner**: Use the vendor's managed-application or orchestrator uninstall. Do not delete protected managed children or bypass the deny assignment, and decide whether shared licences and management services are kept or cancelled. This is outside Terraform.

   Expect: The hub no longer has an external appliance dependency.

6. **Review and remove the owned infrastructure**: Review the destroy plan for the WAN, hub, connection, three VNets, the management peerings, two Bastions, three public IPs and two VMs with disks. The resource group safeguard refuses unexpected leftovers: do not disable it. Keep the approved image, SSH keys and unrelated licence assets. After approval, apply the saved destroy plan the way you apply any plan.

   ```bash
   terraform plan -destroy -input=false -var-file="$APPROVED_INPUTS" \
     -out="$PLAN_DIR/destroy.tfplan"
   terraform show -no-color "$PLAN_DIR/destroy.tfplan" > "$PLAN_DIR/destroy.txt"
   ```

   Expect: Only owned lab resources are listed. After the apply, `terraform state list` is empty; then check the portal and your vendor and licence portals for residual cost.
