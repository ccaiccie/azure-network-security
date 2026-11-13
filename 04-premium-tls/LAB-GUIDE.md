# Lab guide: Azure Firewall Premium TLS inspection

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall Premium, Bastion and the App Service plan bill while they exist.

## Activity 1: Prerequisites and local checks

**Goal.** Run every check that needs no deployment and confirm the plan with all gates closed creates nothing.

**Exam skill.** Know the four gates and that a closed plan proves nothing about TLS.

1. **Local checks and a closed plan**: From the lab folder, with all four gates false.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
   ./scripts/check-local.sh
   terraform fmt -check -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   terraform plan -out=lab.tfplan
   terraform show -no-color lab.tfplan
   ```

   Expect: With `deploy_lab = false` the plan creates **no resources**. That proves nothing about TLS. `init -backend=false` can still download the provider.

2. **Resolve a concrete image and check extensions**

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   az vm image list --subscription "$SUBSCRIPTION_ID" --location "$LOCATION" \
     --publisher Canonical --offer ubuntu-24_04-lts --sku server --all \
     --query '[].version' -o tsv
   az extension show --name azure-firewall -o json
   az extension show --name bastion -o json
   ```

   Expect: A version list to pin in `image_version`; both extensions already present (dynamic install is disabled on purpose).

## Activity 2: Build the closed infrastructure

**Goal.** Create the network, firewall, VM, Bastion, origin plan and logs with inspection still off.

**Exam skill.** Read a plan for the design's key facts: no VM public IP, Premium policy, no test rules yet.

1. **Set deploy_lab and review the plan**: In `terraform.tfvars` set `deploy_lab = true` and leave `enable_tls_inspection`, `tls_prerequisites_confirmed` and `origin_fixture_ready` false. Plan to a file and read it.

   ```bash
   terraform plan -out=lab.tfplan
   terraform show -no-color lab.tfplan
   ```

   Expect: Resource group, two VNets and peerings, Premium firewall and policy, two public IPs, route table, NSG, VM, Bastion, App Service plan and web app, workspace. No `test-rules` group, no policy identity, no `tls_certificate`. Stop here unless the plan is approved.

2. **Apply after approval, then bind to the real state**: Apply the saved plan. A Premium firewall can take several minutes to provision. Then read the outputs and collect the configuration evidence.

   ```bash
   terraform apply lab.tfplan
   source scripts/common.sh
   load_context
   A=$(read_output app_private_ip)
   F=$(read_output firewall_private_ip)
   P=$(read_output firewall_public_ip)
   printf 'A=%s F=%s P=%s H=%s\n' "$A" "$F" "$P" "$H"
   ./scripts/collect-control-plane.sh
   ```

   Expect: `load_context` aborts if the firewall's subscription differs from `SUBSCRIPTION_ID`. The collector saves firewall, policy, rule groups, effective routes and NSGs, peerings and origin access restrictions as JSON. No test rules exist yet, so the workload is default-denied.

## Activity 3: Publish and preflight the origin

**Goal.** Put the synthetic fixture on the App Service and prove both paths work without the firewall.

**Exam skill.** Separate origin readiness from firewall behaviour, so a later failure can only be the firewall.

1. **Build the origin package and record its hash**: Build the ZIP locally and have a reviewer record its SHA256 independently before any upload.

   ```bash
   python3 scripts/build-origin.py
   python3 -m zipfile -l build/origin.zip
   sha256sum build/origin.zip
   ```

   Expect: The ZIP holds only `server.js` and `package.json`. The reviewed hash is the approval, not the file you just built.

2. **Upload the reviewed package**: Only after approval to upload the synthetic fixture. The script rebuilds the ZIP, compares its hash with the reviewed value and refuses on a difference.

   ```bash
   ./scripts/deploy-origin.sh --confirm-synthetic-origin-upload "$REVIEWED_ORIGIN_ZIP_SHA256"
   ```

   Expect: The hash matches, then `az webapp deploy` uploads and restarts the app.

3. **Preflight the origin directly**: Run from the operator /32, outside the inspection path, with a public bundle that excludes the inspection root.

   ```bash
   ./scripts/origin-preflight.sh /approved/public-normal-origin-roots.pem
   ```

   Expect: Both `/allowed` and `/blocked` return HTTP 200 with the right fixture name, path and case ID. A welcome page, 403 or 503 is not readiness.

## Activity 4: Link the CA and enable the test rules

**Goal.** Attach the existing identity and secret to the policy, then switch on the two TLS-terminating rules.

**Exam skill.** Know the three trust relationships and what each gate does and does not prove.

1. **Link the identity and secret, then plan**: After PKI, identity and access are approved, add the existing identifiers to `terraform.tfvars` (identifiers only, never secret values) and plan.

   ```bash
   # terraform.tfvars (identifiers only)
   tls_prerequisites_confirmed = true
   enable_tls_inspection       = true
   tls_identity_id = "<existing user-assigned identity resource ID>"
   tls_secret_uri  = "https://VAULT.vault.azure.net/secrets/NAME/VERSION"
   
   terraform plan -out=tls.tfplan
   terraform show -no-color tls.tfplan
   ```

   Expect: The only changes are the identity and `tls_certificate` on `lab-policy`. Attestation is not proof that the firewall can read the secret.

2. **Apply and wait for the CA to be usable**: Apply the saved plan, then allow time. Microsoft's known-issues page mentions about 5 to 10 minutes for intermediate-CA propagation; wait for real readiness, not a fixed sleep.

   ```bash
   terraform apply tls.tfplan
   ```

   Expect: The policy shows the identity and `approved-inspection-intermediate`. If retrieval fails, keep the next gate false.

3. **Enable the test rules**: Only after the origin passed both direct checks, set `origin_fixture_ready = true`, plan and apply.

   ```bash
   terraform plan -out=rules.tfplan
   terraform apply rules.tfplan
   ```

   Expect: Group `test-rules` (priority 200) exists with `deny-test-url` (100) and `allow-test-origin` (200), both terminating TLS.

## Activity 5: Copy public trust files and check readiness in A

**Goal.** Reach the private VM through Bastion, give it only public certificates and check its tools.

**Exam skill.** Keep management separate from the inspected path, and trust process-local, never the OS store.

1. **Copy the public trust files to A**: Terminal 1 keeps a Bastion tunnel open; terminal 2 copies only public PEM files and connects.

   ```bash
   az network bastion tunnel --subscription "$SUBSCRIPTION_ID" -g "$RG" -n "$BASTION" \
     --target-resource-id "$APP_VM_ID" --resource-port 22 --port 50022
   # second terminal
   scp -P 50022 -i "$SSH_KEY" /approved/inspection-root-public.pem "$ADMIN@127.0.0.1:inspection-root-public.pem"
   scp -P 50022 -i "$SSH_KEY" /approved/normal-origin-roots-public.pem "$ADMIN@127.0.0.1:normal-origin-roots-public.pem"
   ssh -p 50022 -i "$SSH_KEY" "$ADMIN@127.0.0.1"
   ```

   Expect: A shell on A. Keep SSH host-key checking on. Never copy a PFX or private key.

2. **Check readiness inside A**

   ```bash
   cloud-init status --wait
   ip -4 -o addr show
   cat /etc/azure-tls-lab.json
   resolvectl status
   curl -V
   openssl version
   python3 /usr/local/lib/azure-tls/public-ca-check.py "$HOME/inspection-root-public.pem"
   python3 /usr/local/lib/azure-tls/public-ca-check.py "$HOME/normal-origin-roots-public.pem"
   ```

   Expect: A = 10.10.1.10, F as DNS, OpenSSL-backed curl, OpenSSL 3, both bundles contain only valid public certificates. The checker cannot verify that the negative bundle excludes the inspection root: you confirm that.

## Activity 6: Run the probes

**Goal.** Run the allowed, blocked and untrusted cases (and the optional next-hop check).

**Exam skill.** Know what each outcome proves: inspection, URL deny, client trust, and what a curl exit code does not prove.

1. **Run the probes**

   ```bash
   tls-probe allowed "$HOME/inspection-root-public.pem"
   tls-capture-chain "$HOME/inspection-root-public.pem"
   tls-probe blocked "$HOME/inspection-root-public.pem"
   tls-probe untrusted "$HOME/normal-origin-roots-public.pem"
   ```

   Expect: Evidence folders under `~/tls-evidence/`. Each case prints `curl_exit`, the tuple and `RESULT=NEEDS_REVIEW`; `allowed` also prints `ORIGIN_IDENTITY=MATCH|MISMATCH`.

2. **Optional: next hop for the real destination**

   ```bash
   az network watcher show-next-hop \
     --subscription "${SUBSCRIPTION_ID:?Set approved subscription}" \
     -g "$RG" --vm app --nic app-nic --source-ip 10.10.1.10 --dest-ip "$DCLIENT" -o json
   ```

   Expect: Next hop VirtualAppliance F. Use the observed Dclient, not F. Requires an existing Network Watcher; do not create one for this.

## Activity 7: Read the evidence

**Goal.** Turn the probes into verdicts with the firewall, origin and IDPS logs.

**Exam skill.** Prove inspection with `IsTlsInspected = true`, correlate by source port and time, and treat empty results as inconclusive.

1. **Run the application-rule query**: Copy the query file, replace the firewall resource ID and the UTC window with the real values from the probe, then run it.

   ```bash
   source scripts/common.sh
   load_context
   WORKSPACE=$(read_output workspace_customer_id)
   mkdir -p evidence
   cp queries/application.kql evidence/application.kql
   # edit the let lines: firewall resource ID and the UTC window of the probe
   az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/application.kql)" -o json
   ```

   Expect: Rows for 10.10.1.10: Allow `allow-approved-origin` with `IsTlsInspected = true` and the path in `TargetUrl`; Deny `deny-blocked-path` for `/blocked`. Match by `SourcePort` and time: the table has no destination IP column.

2. **Read the origin side**: Run `queries/origin.kql`, `queries/origin-access.kql` and, with the exact case ID filled in, `queries/origin-console.kql` the same way.

   Expect: The allowed case has an origin record with its case ID in the user agent. The blocked case has none. The access audit shows P allowed by `allow-lab-firewall`.

3. **Check IDPS and record the verdicts**: Run `queries/idps.kql` the same way. Then mark each case in `RESULTS.template.md` as PASSED, FAILED, INCONCLUSIVE or NOT RUN.

   Expect: Benign traffic need not create an IDPS row, so an empty table proves nothing. Logs arrive late: an empty first result is inconclusive.

## Activity 8: Roll back and destroy

**Goal.** Close the rules, unlink the CA, then remove everything the lab built and prove it is gone.

**Exam skill.** Know that rolling back rules stops no billing, and never delete the pre-existing PKI.

1. **Save non-secret evidence first**: Probe folders, collector JSON, query results. Never publish raw state, saved plans or publishing profiles: AzureRM's Linux Web App can store `site_credential` values in state.

2. **Close the policy**: Review and apply `origin_fixture_ready = false`. This removes `test-rules` and returns the workload to default deny. It stops no billing.

3. **Unlink the CA if required**: With origin-ready false, review `enable_tls_inspection = false`. This removes the identity and certificate reference from the policy but does **not** revoke the identity's Key Vault access or delete the CA. Keep `deploy_lab = true` if you only want withdrawal.

4. **End the tunnel**: Ctrl-C the SSH session and the Bastion tunnel. Process-local trust disappears when the probes exit; there is no OS trust change to undo.

5. **Review and approve a destroy plan**

   ```bash
   RG=$(terraform output -raw resource_group_name)
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   ```

   Expect: Only dedicated lab resources. Setting `deploy_lab = false` on an existing state also plans deletion.

6. **Verify after the approved deletion**

   ```bash
   terraform state list
   az group exists --subscription "${SUBSCRIPTION_ID:?Set approved subscription}" --name "$RG"
   ```

   Expect: Empty state and `false`. Check for leftover firewall, Bastion, public IPs, VM disk, App Service plan, policy and workspace. Never delete the pre-existing Key Vault, CA, identity or grants as lab clean-up.
