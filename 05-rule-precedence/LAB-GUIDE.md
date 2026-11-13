# Lab guide: Azure Firewall Policy rule precedence

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall and Bastion bill while they exist. Expected results are design predictions from Microsoft's documented processing order (group priority first, then rule type inside a group), not observations. The `README.md`, `RESULTS.template.md` and mocked tests that came with the lab still carry the original claim that the 65000 override decides first; they are kept unchanged.

## Activity 1: Prerequisites and local checks

**Goal.** Confirm the right subscription and run every check that needs no deployment.

**Exam skill.** Know what must exist before a deployment: providers, extensions, a concrete image version and checks that run offline.

1. **Read-only prerequisite checks**: Confirm the subscription, the provider registrations and that a concrete Ubuntu 24.04 image version exists in your approved region. Dynamic extension installation stays off.

   ```bash
   export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
   az account show --query '{subscription:id,tenant:tenantId,name:name}' -o json
   az provider show --namespace Microsoft.Network --query registrationState -o tsv
   az vm image list --subscription "$SUBSCRIPTION_ID" --location "$LOCATION" \
     --publisher Canonical --offer ubuntu-24_04-lts --sku server --all \
     --query '[].version' -o tsv
   az extension show --name azure-firewall -o json
   az extension show --name bastion -o json
   ```

   Expect: The right subscription, the provider `Registered`, a concrete image version to pin, and both extensions already installed. Region capacity for Azure Firewall Standard is a separate check against Microsoft's current capacity table.

2. **Prepare inputs and run the local checks**: From the `terraform` folder (the original `lab`). Keep every gate closed for now. The public key must already exist.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_ssh_public_key="$(cat /approved/path/existing-key.pub)"
   ./scripts/check-local.sh
   ```

   Expect: Bash syntax, source-contract and helper tests pass. They test helpers and the fixture, not Azure.

3. **Terraform checks**: Only after the provider install is approved. `init` needs the provider download.

   ```bash
   terraform init -backend=false
   terraform fmt -check -recursive
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: The mocked plan-only runs pass. They still depend on the real AzureRM 5.12.0 schema, so a failure here is a schema problem, not an Azure problem.

## Activity 2: Plan, review and deploy in closed mode

**Goal.** Preview what Terraform will create, check it against the design, and only when approved build it with every test rule group absent.

**Exam skill.** Read a plan for the design's key facts: no VM public IP, two public IPs, one policy with DNS proxy on and no user groups yet.

1. **Set the inputs for a closed deployment**: Edit `terraform.tfvars` (nonsecret, never committed). The location has no default on purpose.

   ```bash
   subscription_id       = "<approved subscription UUID>"
   location              = "<approved region with capacity>"
   image_version         = "<concrete version from Activity 1>"
   deploy_lab            = true
   fixtures_ready        = false
   policy_mode           = "closed"
   experiments_confirmed = false
   ```

   Expect: Four gates visible: only `deploy_lab` is true. `closed` creates infrastructure, DNS and Bastion but no test rule groups.

2. **Plan and review**: Check: right subscription and region, only dedicated resources, no VM public IP, exactly two public IPs (firewall and Bastion), spoke DNS pointing at the **computed** firewall IP, `default_outbound_access_enabled = false`, no rule collection groups, acceptable cost.

   ```bash
   terraform plan -out=closed.tfplan
   terraform show -no-color closed.tfplan
   ```

   Expect: A plan that creates only lab resources. **Stop here unless deployment and cost are approved.**

3. **Apply (authorised operator only)**: Apply the saved plan. The firewall takes many minutes.

   ```bash
   terraform apply closed.tfplan
   terraform output
   ```

   Expect: Outputs such as `firewall_private_ip` (F), `firewall_public_ip`, `app_private_ip`, `backend_private_ip`, `policy_mode` = `closed`. A successful apply proves only that Azure accepted the resources.

## Activity 3: Control-plane evidence, Bastion tunnels and readiness

**Goal.** Save what Azure says is configured, reach both private VMs, and prove the fixture and DNS are healthy before any policy test.

**Exam skill.** Separate the management path from the test path, and know why local controls must pass before a firewall result means anything.

1. **Bind to state and collect the control plane**: The helper aborts if the approved subscription does not match the state. It only reads.

   ```bash
   export SUBSCRIPTION_ID="<approved subscription UUID>"
   source scripts/common.sh
   load_context
   ./scripts/collect-control-plane.sh
   ```

   Expect: A new `evidence/control-<UTC>-<pid>` folder with rule groups (empty in closed mode), effective routes and NSGs for both NICs, peerings and DNS.

2. **Tunnel to B and check the fixture**: In its own terminal. B is `backend`.

   ```bash
   az network bastion tunnel --subscription "$SUBSCRIPTION_ID" -g "$RG" \
     -n "$(read_output bastion_name)" --target-resource-id "$(read_output backend_vm_id)" \
     --resource-port 22 --port 50022
   ssh -p 50022 -i "$SSH_KEY" "$ADMIN@127.0.0.1"
   # on B:
   cloud-init status --wait
   policy-ready
   ```

   Expect: Both units active on 10.20.1.10 and four local HTTP 200s (both names on 8080 and 8081). This tests the listener only, never the firewall.

3. **Tunnel to A and check DNS**: Same way, local port 50023 and `app_vm_id`.

   ```bash
   getent ahostsv4 allowed.policy.test
   getent ahostsv4 denied.policy.test
   cat /etc/hosts
   ```

   Expect: Both names resolve to 10.20.1.10 only, with no hosts-file override.

## Activity 4: Phase 0 and phase 1: closed, then application

**Goal.** See the default deny, then add the application rules and watch the proxy.

**Exam skill.** Explain the default deny with evidence, and why the allowed request reaches B from a firewall instance address, not from A.

1. **Phase 0: closed**: No test rule groups exist, so there is no explicit rule to name.

   ```bash
   policy-probe allowed
   ```

   Expect: No fixture response. The proof is a default-deny row with an `ActionReason`, not the timeout. The probe always ends with `RESULT=NEEDS_REVIEW`: a pass needs the log row, the mode and the backend peer.

2. **Switch to application mode**: Review the plan first. The mode is not in the VM's cloud-init, so the VMs should not be replaced; check anyway.

   ```bash
   terraform plan -var fixtures_ready=true -var policy_mode=application -out=app.tfplan
   terraform apply app.tfplan
   ```

   Expect: Two groups appear: `app-controls` (200) and `negative-controls` (300). Wait until the export shows them before testing.

3. **Phase 1: the probes on A**: Run the probes on A. Use a fresh connection every time.

   ```bash
   policy-probe allowed
   policy-probe denied
   policy-probe alternate-port
   policy-probe allowed
   ```

   Expect: `allowed` gives 200 with `FIREWALL_SUBNET_PROXY_SOURCE` (an address I in 10.0.1.0/26). `denied` ends at `deny-denied-host`. `alternate-port` ends at `deny-app-alternate-port`.

## Activity 5: Phase 2 and phase 3: the override modes

**Goal.** Add the 65000 network override as shipped, once as an Allow and once as a Deny, and test the prediction that group 200 is read first.

**Exam skill.** Explain why a network rule in a late group does not take over, and name what would change if it shared a group or came first.

1. **Phase 2: network-allow**: Set `experiments_confirmed` and the mode, review the plan, apply. Only `network-override` (65000) should be added.

   ```bash
   terraform plan -var fixtures_ready=true -var experiments_confirmed=true -var policy_mode=network-allow -out=na.tfplan
   terraform apply na.tfplan
   policy-probe allowed
   policy-probe denied
   policy-probe alternate-port
   ```

   Expect: **Predicted from the documented order:** `allowed` is still 200 from an address I (application Allow), `denied` is still refused (application Deny), `alternate-port` is still refused. There is no network row for A to B on 8080. **If instead** `denied` returns 200 with `DIRECT_APP_SOURCE` and a network Allow row `allow-app-backend` appears, your firewall read the override first: keep the exports and treat the correction in this guide as wrong for that deployment.

2. **Phase 3: network-deny**: The Deny replaces the Allow (the mode enum allows only one).

   ```bash
   terraform plan -var fixtures_ready=true -var experiments_confirmed=true -var policy_mode=network-deny -out=nd.tfplan
   terraform apply nd.tfplan
   policy-probe allowed
   policy-probe denied
   ```

   Expect: **Predicted:** `allowed` is still 200 (application Allow, group 200), `denied` is still refused. The 65000 Deny cannot block what group 200 already allowed. **If instead** both names fail with a `deny-app-backend` row, the override was read first.

3. **List the groups Azure really holds**: The export is the ground truth for group and collection priorities. Field names are as printed by your az version.

   ```bash
   ./scripts/collect-control-plane.sh
   CTRL=$(ls -d evidence/control-* | tail -1)
   python3 -c 'import json,sys; [print(g["priority"], g["name"]) for g in json.load(open(sys.argv[1]))]' "$CTRL/rule-groups.json"
   ```

   Expect: Priorities 200 `app-controls`, 300 `negative-controls`, 65000 `network-override`, in that order of evaluation.

4. **Optional: the same-group variation**: In a **copy** of the folder (the shipped mock tests and source checks assert the original layout and will fail after the edit). In `module/main.tf`, move the override's `network_rule_collection` into the `app-controls` group and keep the `network-override` group out of the plan. Changing only the override group's `priority` from 65000 to 100 is a simpler variant: it also makes the network rule decide, but because its **group** is read first.

   ```hcl
   network_rule_collection {
     name     = "allow-exact-backend"
     priority = 65000
     action   = "Allow"
     rule {
       name                  = "allow-app-backend"
       protocols             = ["TCP"]
       source_addresses      = ["10.10.1.10/32"]
       destination_addresses = ["10.20.1.10/32"]
       destination_ports     = ["8080"]
     }
   }
   ```

   Expect: Plan, apply and probe as in Phase 2. Predicted: `denied` now returns 200 with `DIRECT_APP_SOURCE`, a network Allow row names `allow-app-backend`, and the application Deny is still in the export. That is the type order, made visible.

## Activity 6: Query the logs and prove the decider

**Goal.** Turn the probes into a verdict: the rule row, the backend journal and the routes.

**Exam skill.** Join evidence by source port and time, and know that a missing row is inconclusive, not a pass.

1. **Make query copies with the real firewall and time window**: The lab's query files carry placeholders for the subscription and a UTC window. Take the bounds from the probe's `timing.txt`.

   ```bash
   WORKSPACE=$(read_output workspace_customer_id)
   START=2026-11-12T10:00:00Z   # from timing.txt started_utc
   END=2026-11-12T10:05:00Z     # from timing.txt completed_utc
   mkdir -p evidence
   for q in network application; do
     sed -e "s|/subscriptions/REPLACE/|/subscriptions/$SUBSCRIPTION_ID/|" \
         -e "s|2000-01-01T00:00:00Z|$START|" -e "s|2000-01-01T00:05:00Z|$END|" \
         queries/$q.kql > evidence/$q.kql
   done
   ```

   Expect: Two edited query files. The dates above are only an example; use your own UTC bounds.

2. **Run the network and application queries**: A table-not-found or permission error is a blocker, not a negative result. Ingestion can lag.

   ```bash
   az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/network.kql)" -o json > evidence/network.json
   az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/application.kql)" -o json > evidence/application.json
   ```

   Expect: Rows that name the deciding rule, for example `deny-app-alternate-port` in the network table and `allow-approved-host` or `deny-denied-host` in the application table, matched to the client source port and time.

3. **Find the case on B**: No match is normal for a denied request, and `grep` then exits 1. Absence alone proves nothing.

   ```bash
   : "${CASE_ID:?Set the exact recorded synthetic case ID}"
   sudo journalctl -u azure-policy-fixture@8080.service -u azure-policy-fixture@8081.service \
     --since '15 minutes ago' --no-pager -o cat | grep -F -- "$CASE_ID"
   ```

   Expect: For an allowed request: the case ID, host and `peer_ip`. I (in 10.0.1.0/26) means the application proxy; A (10.10.1.10) means a network rule forwarded it.

4. **Record the results**: Mark each case PASSED, FAILED, INCONCLUSIVE or NOT RUN in `RESULTS.template.md`. The template's 'expected' columns follow the original guide (network rule decides in the override modes); write what you observed and which reading it supports.

   Expect: A results file where every case has the evidence that supports it.

## Activity 7: Restore, close and destroy

**Goal.** Restore the baseline, prove it, then remove everything the lab built.

**Exam skill.** Know that restoring the policy and removing the lab are different jobs, and that stopping a VM does not stop firewall or Bastion billing.

1. **Keep the evidence**: Copy the evidence folders and journals off the VMs first. The journal is not persistent across reboots.

2. **Phase 4: restore application mode**: Select `application` again and `experiments_confirmed=false`. Confirm `network-override` is gone, then repeat the Phase 1 probes.

   ```bash
   terraform plan -var fixtures_ready=true -var experiments_confirmed=false -var policy_mode=application -out=restore.tfplan
   terraform apply restore.tfplan
   policy-probe allowed
   policy-probe denied
   policy-probe alternate-port
   ```

   Expect: The group `network-override` is absent from the export, and the original split and the proxy source I are back.

3. **End sessions**: Stop SSH sessions and Bastion tunnels with Ctrl-C.

4. **Destroy through the approved process**: Review the destroy plan against the dedicated state and resource group only. Setting `deploy_lab=false` on an existing state also plans destruction.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: Only lab resources are listed and then deleted: firewall, Bastion, both VMs, disks, both public IPs, DNS zone, workspace.

5. **Verify removal**

   ```bash
   az group exists --subscription "$SUBSCRIPTION_ID" --name "$RG"
   az resource list --subscription "$SUBSCRIPTION_ID" \
     --resource-group "$RG" --query '[].{name:name,type:type,id:id}' -o json
   ```

   Expect: `false`. If the group still exists, list the leftovers without deleting unrelated objects.
