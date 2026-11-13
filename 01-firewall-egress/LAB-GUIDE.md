# Lab guide: Azure Firewall hub-and-spoke egress

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall and Bastion bill while they exist.

## Activity 1: Prerequisites and local checks

**Goal.** Confirm the right subscription and run every check that needs no deployment.

**Exam skill.** Know what must exist before a deployment: providers, VM size, image and a plan that is checked offline.

1. **Read-only prerequisite checks**: Confirm the subscription, provider registrations, VM size and image availability in your approved region.

   ```bash
   az account show --query '{subscription:id,tenant:tenantId,name:name}' -o json
   az provider show --namespace Microsoft.Network --query registrationState -o tsv
   az vm list-skus --location eastus --size Standard_B1s --all -o table
   az vm image list --location eastus --publisher Canonical \
     --offer ubuntu-24_04-lts --sku server --all -o table
   ```

   Expect: Correct subscription; providers `Registered`; the SKU and image are listed. A listing does not guarantee capacity.

2. **Prepare inputs and run local checks**: From the `lab` folder, copy the example variables, edit them locally and supply the public key from the environment.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
   ./scripts/check-local.sh
   terraform fmt -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/policy_modes.tftest.hcl
   ```

   Expect: All local checks pass. The tests use a mock provider and plan only. `init` may still contact the registry to download the provider.

## Activity 2: Plan, review and apply

**Goal.** Preview what Terraform will create, check it against the design, and (only when approved) build it.

**Exam skill.** Read a plan for the design's key facts: no VM public IP, two public IPs, computed firewall IP in the route and DNS.

1. **Plan and review**: Check: right subscription and region, only dedicated resources, no VM public IP, exactly two public IPs (firewall and Bastion), route next hop and spoke DNS both reference the **computed** firewall IP, `default_outbound_access_enabled = false`, the intended `policy_mode`, acceptable cost.

   ```bash
   terraform plan -out=lab.tfplan
   terraform show -no-color lab.tfplan
   ```

   Expect: A plan that creates only lab resources. **Stop here unless deployment and cost are approved.**

2. **Apply (authorised operator only)**

   ```bash
   terraform apply lab.tfplan
   terraform output
   ```

   Expect: Outputs including `firewall_private_ip`, `firewall_public_ip`, `vm_private_ip`, `policy_mode`. A successful apply proves only that Azure accepted the resources, not that egress works.

## Activity 3: Record the control-plane evidence

**Goal.** Save what Azure says is configured, including effective routes and effective NSGs.

**Exam skill.** Prove steering with effective routes and next hop, not with the route table resource.

1. **Collect control-plane evidence**: On your workstation, run the read-only collector. It saves Terraform outputs, firewall, public IPs, NIC, **effective routes**, **effective NSGs**, peerings, subnet, route table, policy, rule collection group, diagnostic settings and VM state as JSON.

   ```bash
   ./scripts/collect-control-plane.sh
   ```

   Expect: Both peerings `Connected`; NIC 10.20.1.4 with no public IP; `defaultOutboundAccess: false`; effective route `0.0.0.0/0 → VirtualAppliance <actual F>`.

2. **Optional: Network Watcher next hop**: Copy an IPv4 address the VM actually resolved, then ask Azure which route it selects. This needs an existing Network Watcher in the region; do not create one just for this step.

   ```bash
   TEST_IP='<actual public IPv4 observed inside the VM>'
   az network watcher show-next-hop -g "$RG" --vm vm-egress --nic nic-egress \
     --source-ip 10.20.1.4 --dest-ip "$TEST_IP" -o json
   ```

   Expect: `nextHopType: VirtualAppliance` and the actual F. This proves route selection only, not permission or delivery.

## Activity 4: Connect through Bastion and run the guest harness

**Goal.** Reach the private VM with no public IP and run the test cases.

**Exam skill.** Separate the management path from the egress path, and know what each test proves.

1. **SSH to the VM through Bastion**

   ```bash
   RG=$(terraform output -raw resource_group_name)
   VM_ID=$(terraform output -raw vm_id)
   BASTION=$(terraform output -raw bastion_name)
   USER_NAME=$(terraform output -raw admin_username)
   az network bastion ssh --resource-group "$RG" --name "$BASTION" \
     --target-resource-id "$VM_ID" --auth-type ssh-key \
     --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
   ```

   Expect: A shell on `vm-egress`. Verify the host key through your normal process. Run this from a local workstation, not Cloud Shell.

2. **Run the guest harness inside the VM**: Cloud-init installed the harness at `/usr/local/bin/egress-demo` and its settings in `/etc/egress-demo.json`. It does not run automatically.

   ```bash
   cloud-init status --wait
   cat /etc/egress-demo.json
   command -v curl python3 getent ip
   /usr/local/bin/egress-demo
   ```

   Expect: An evidence folder `~/egress-evidence-<UTC>` holding resolver settings, DNS answers and one fresh curl per case (`allowed-https`, `egress-ip`, `http-negative`, `unlisted-https`). The session prints whether the echo body **MATCHES** P, and either `DNS_BYPASS_VERDICT=NOT_RUN` (no `dig`) or `NEEDS_REVIEW`.

## Activity 5: Query the firewall logs

**Goal.** Turn the evidence into a verdict using Log Analytics.

**Exam skill.** Correlate time, source port and rule to prove a decision; know the pre-SNAT tuple is logged.

1. **Run the combined decision query**: A denied flow may land in a different table than an allowed one, so start with the combined query. Replace the placeholder with the firewall resource ID.

   ```bash
   WORKSPACE=$(terraform output -raw workspace_customer_id)
   FW_ID=$(terraform output -raw firewall_id)
   mkdir -p evidence
   sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/decisions.kql > evidence/decisions.kql
   az monitor log-analytics query --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/decisions.kql)" -o json > evidence/decisions.json
   ```

   Expect: JSON rows for 10.20.1.4: Allow for TCP/443 and Deny for TCP/80, timed to match the curl cases. Ingestion can lag up to 30 minutes, so an empty result is inconclusive.

2. **Run the DNS query**: Prove the VM used the proxy.

   ```bash
   sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/dns.kql > evidence/dns.kql
   az monitor log-analytics query --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/dns.kql)" -o json > evidence/dns.json
   ```

   Expect: `AZFWDnsQuery` rows from 10.20.1.4 for the names the harness resolved. Resolving a name is not permission.

3. **Record the results**: Mark each case PASSED, FAILED, INCONCLUSIVE or NOT RUN in `RESULTS.template.md`.

   Expect: A results file where every case has the evidence that supports it.

## Activity 6: Switch to application mode (optional)

**Goal.** See the same destinations judged by hostname instead of resolved IPs.

**Exam skill.** Explain why Bing is conditional in network mode and denied in application mode.

1. **Change the mode and review the plan**: Set `policy_mode` to `application` in `terraform.tfvars` (or pass it on the command line), then plan. Changing the mode also changes the VM's cloud-init data, so the plan may replace the VM. Read the plan before you apply it.

   ```bash
   terraform plan -var 'policy_mode=application' -out=app.tfplan
   terraform show -no-color app.tfplan
   ```

   Expect: The network collection `allow-selected-tcp443` is removed and the application collection `allow-selected-https` is added. Stop here unless the change is approved.

2. **Apply, reconnect and rerun the harness**: After the apply, reconnect through Bastion and run the harness again.

   ```bash
   terraform apply app.tfplan
   /usr/local/bin/egress-demo
   ```

   Expect: `allowed-https` and `egress-ip` still succeed. `unlisted-https` (www.bing.com) is now denied. `http-negative` is still denied.

3. **Read the application-rule log**: Use the application query instead of the network query (replace `FIREWALL_RESOURCE_ID` first).

   ```bash
   sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/application.kql > evidence/application.kql
   ```

   Expect: Allow rows carry the FQDN taken from the SNI. The Bing attempt shows a Deny row in `AZFWApplicationRule`.

## Activity 7: Destroy and verify

**Goal.** Remove everything the lab built and prove it is gone.

**Exam skill.** Know that deallocation is not deletion and that stopping the VM alone does not stop firewall or Bastion billing.

1. **Save the evidence first**: Copy the guest folder, control-plane JSON and query results. Do not publish subscription IDs, topology or state without review.

2. **Review a destroy plan**

   ```bash
   RG=$(terraform output -raw resource_group_name)
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   ```

   Expect: Only dedicated lab resources are listed for deletion.

3. **Destroy after approval and verify**

   ```bash
   terraform apply destroy.tfplan
   terraform state list
   az group exists --name "$RG"
   ```

   Expect: Empty state and `false`. If deletion fails, keep the state and inspect what remains. The resource-group deletion guard refuses to delete a group that still has resources Terraform did not create; do not disable it.

4. **Check for orphans**: Look for leftover firewall, Bastion, VM disks, public IPs, policy and workspace. Billing views lag. Stopping the VM alone does not stop firewall or Bastion charges.
