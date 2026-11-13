# Lab guide: Azure Firewall east-west inspection

Run the activities in order from the `terraform` folder (the original `lab`). Nothing here has been applied; every command is a procedure for a future, approved run. Azure Firewall and Bastion bill while they exist. Activities 7 and 8 are optional experiments.

## Activity 1: Prerequisites and local checks

**Goal.** Confirm the subscription, providers, VM size and image, and run every check that needs no deployment.

**Exam skill.** Know what must exist before a deployment, and what the offline checks do and do not prove.

1. **Check the subscription, providers, size and image**: These read-only commands need no deployment. Run them after you sign in with an approved method.

   ```bash
   az account show --query '{subscription:id,tenant:tenantId,name:name}' -o json
   az provider show --namespace Microsoft.Network --query registrationState -o tsv
   az provider show --namespace Microsoft.Compute --query registrationState -o tsv
   az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
   az provider show --namespace Microsoft.Insights --query registrationState -o tsv
   az vm list-skus --location eastus --size Standard_B1s --all -o table
   az vm image list --location eastus --publisher Canonical \
     --offer ubuntu-24_04-lts --sku server --all -o table
   ```

   Expect: The right subscription, `Registered` four times, and the VM size and a concrete Ubuntu image version listed. A listing is not a capacity guarantee, and `eastus` and `Standard_B1s` are samples.

2. **Prepare the variables and run the local checks**: Copy the example variables and fill in the subscription, region, image version and tags. Choose `enable_same_vnet` now: changing it later can replace A and B. Export only the public key, then run the offline checks.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
   ./scripts/check-local.sh
   terraform fmt -recursive
   terraform init -backend=false
   terraform validate
   terraform test -filter=tests/baseline.tftest.hcl
   ```

   Expect: Local checks pass and the mocked plan tests pass. `init -backend=false` may still download providers, so it is not inherently offline.

## Activity 2: Plan, review and apply

**Goal.** Preview what Terraform will create, check it against the design, and, only when approved, build it.

**Exam skill.** Read a plan for the design's key facts: no workload public IP, two service public IPs, four peerings, associated route tables and NSGs.

1. **Create a plan and read it**: A plan creates nothing. Check the identity, region, cost, no workload public IP, two service public IPs, four peerings, the route and NSG associations and the private network rules.

   ```bash
   terraform plan -out=lab.tfplan
   terraform show -no-color lab.tfplan
   ```

   Expect: A reviewed plan. Stop here for authorization.

2. **Apply the reviewed plan and read the outputs**: Only after approval. The firewall takes several minutes. Billing starts.

   ```bash
   terraform apply lab.tfplan
   terraform output experiment_settings
   terraform output firewall_private_ip
   ```

   Expect: Outputs show the baseline flags and the real firewall address F. Successful provisioning does not prove that listeners or traffic work.

## Activity 3: Record the control-plane evidence

**Goal.** Save what Azure says is configured, including the effective routes and effective NSGs of both VMs.

**Exam skill.** Prove steering in both directions with effective routes and next hop, not with the route table resource.

1. **Run the read-only collector**: It saves the outputs, firewall, policy, rule group, diagnostics, and for each VM the NIC, effective routes, effective NSGs, subnet, route table and state.

   ```bash
   ./scripts/collect-control-plane.sh
   terraform output experiment_settings
   ```

   Expect: A folder `evidence/control-<UTC time>/` with JSON files. The flags show the baseline values: `explicit_remote_routes=true`, `return_route_blackhole=false`, `enable_same_vnet=false`, `same_vnet_return_route_enabled=true`.

2. **Check both next hops (optional)**: Only if an authorized Network Watcher already exists. A missing Watcher means NOT RUN; do not create one just for this.

   ```bash
   RG=$(terraform output -raw resource_group_name)
   az network watcher show-next-hop -g "$RG" --vm app --nic app-nic \
     --source-ip 10.10.1.10 --dest-ip 10.20.1.10 -o json
   az network watcher show-next-hop -g "$RG" --vm db --nic db-nic \
     --source-ip 10.20.1.10 --dest-ip 10.10.1.10 -o json
   ```

   Expect: Both results: `VirtualAppliance` with the actual F. This is route evidence, not proof that the firewall or the application worked.

## Activity 4: Reach the VMs and verify the listeners

**Goal.** Open private sessions through Bastion and prove that every test server is ready before any negative test.

**Exam skill.** Separate the management path from the test path, and know why a negative result needs a verified listener.

1. **Open a Bastion session to each VM**: Use the local workstation, not Cloud Shell. Open the second session in a separate terminal.

   ```bash
   RG=$(terraform output -raw resource_group_name)
   BASTION=$(terraform output -raw bastion_name)
   USER_NAME=$(terraform output -raw admin_username)
   APP_ID=$(terraform output -raw app_vm_id)
   DB_ID=$(terraform output -raw db_vm_id)
   az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$APP_ID" \
     --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
   # separate terminal: the same command with --target-resource-id "$DB_ID"
   ```

   Expect: A shell on each VM. Verify host keys with your approved process; never disable host-key checking or add a public IP.

2. **Verify the listeners in each VM**: Cloud-init wrote the fixtures. Check them before any negative probe counts.

   ```bash
   cloud-init status --wait
   sudo cat /var/log/azure-ew-readiness.log
   sudo /usr/local/bin/ew-ready
   sudo ss -lntp
   sudo systemctl status 'azure-ew-fixture@8080.service' --no-pager
   # on B only:
   sudo systemctl status 'azure-ew-fixture@8081.service' --no-pager
   ```

   Expect: `LOCAL_FIXTURES_READY` on A (8080) and B (8080 and 8081). This is local readiness only. Keep a fresh readiness record with its UTC time: a negative probe without it is inconclusive.

## Activity 5: Run the four probes

**Goal.** Make the positive, alternate-port, reverse-new and repeated positive connections and save the evidence.

**Exam skill.** Know what each probe proves and why curl alone is never the verdict.

1. **Run the first two probes in A**: Each call makes one fresh connection and saves headers, body, local and remote address and port, and the curl status.

   ```bash
   /usr/local/bin/ew-probe positive
   /usr/local/bin/ew-probe alternate-port
   ```

   Expect: Positive: HTTP 200 with `peer_ip=10.10.1.10`, `server_ip=10.20.1.10`, port 8080 and `FIXTURE_IDENTITY=MATCH`. Alternate-port: no successful response. Every run ends with `RESULT=NEEDS_REVIEW`, because the helper never infers a firewall verdict.

2. **Run the reverse probe in B**: After you have checked A's listener, start a new connection from B toward A.

   ```bash
   /usr/local/bin/ew-probe reverse-new
   ```

   Expect: No successful response from A. Do not expect a particular timeout or reset: the verdict comes from the firewall log, not from curl.

3. **Repeat the positive probe in A**: This shows that normal replies still work after the reverse deny.

   ```bash
   /usr/local/bin/ew-probe positive
   ```

   Expect: Same positive result as before. Record each probe in `RESULTS.template.md` as PASSED, FAILED, INCONCLUSIVE or NOT RUN.

## Activity 6: Read the journals and firewall logs

**Goal.** Turn the evidence into a verdict by matching case ID, time, source port and rule name.

**Exam skill.** Correlate a probe with a named rule; know the log is a decision record, not a packet capture.

1. **Read the fixture journals**: In B for the positive window, and in A for the reverse window. Match the case ID, not just any request, because readiness calls also appear.

   ```bash
   sudo journalctl -u azure-ew-fixture@8080.service --since '10 minutes ago' \
     --utc --no-pager -o cat      # in B
   sudo journalctl -u azure-ew-fixture@8081.service --since '10 minutes ago' \
     --utc --no-pager -o cat      # in B
   ```

   Expect: B's journal shows the positive case with `peer_ip` 10.10.1.10. A missing row is not a firewall-deny proof.

2. **Query the firewall decisions**: Replace the placeholder with the firewall resource ID, then query the workspace by its customer GUID.

   ```bash
   FW_ID=$(terraform output -raw firewall_id)
   WORKSPACE=$(terraform output -raw workspace_customer_id)
   mkdir -p evidence
   sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/network.kql > evidence/network.kql
   az monitor log-analytics query --workspace "$WORKSPACE" \
     --analytics-query "$(cat evidence/network.kql)" -o json > evidence/network-decisions.json
   ```

   Expect: Rows with `Allow` for `allow-app-to-test`, and `Deny` for `deny-app-alternate-port` and `deny-reverse-new`, with the source ports your probes recorded. Ingestion can lag up to about 30 minutes, so an empty result is inconclusive.

3. **Capture packets on both ends (optional)**: Only if tcpdump is already installed and approved. Use a separate file in each VM and send only the synthetic fixture traffic.

   ```bash
   sudo timeout 25 tcpdump -ni any -s 96 \
     'tcp and host 10.10.1.10 and host 10.20.1.10 and port 8080' \
     -w /tmp/ew-positive-headers.pcap
   ```

   Expect: Both captures show the same unchanged tuple. A capture proves what each host saw, not which Azure path carried the packet.

## Activity 7: Route experiments and rollback (optional)

**Goal.** Break the return path on purpose, then restore the baseline and prove it is restored.

**Exam skill.** Tell a routing failure from a firewall deny, and know why removing a /16 proves nothing.

1. **Return-route blackhole**: Starting from the baseline, add the /32 None route to `db-inspect`. Prefer to set the variable in the owning `.tfvars` file; the command line below is for a one-off plan. Review the plan and obtain approval.

   ```bash
   terraform plan -var 'return_route_blackhole=true' -out=bh.tfplan
   terraform show -no-color bh.tfplan
   ```

   Expect: The plan adds only `experiment-return-blackhole` (10.10.1.10/32 to None) to `db-inspect`. After the apply, B's next hop for A is None, and a new positive probe fails while the firewall can still log Allow. A routing failure, not a firewall deny.

2. **Default-route-only variant (optional)**: Remove only the two remote /16 routes. The /0 routes still point to F.

   ```bash
   terraform plan -var 'explicit_remote_routes=false' -out=dro.tfplan
   terraform show -no-color dro.tfplan
   ```

   Expect: The plan removes the two `remote-spoke` routes. The positive probe still works, which shows that deleting a /16 proves nothing about return routing.

3. **Restore the exact baseline**: Return both flags to their baseline values, remove any one-off overrides so Terraform does not drift, and collect the evidence again.

   ```bash
   terraform plan -out=restore.tfplan
   terraform show -no-color restore.tfplan
   ./scripts/collect-control-plane.sh
   ```

   Expect: The experimental route is gone and both /16 routes are back. Re-run `ew-ready` and all four probes. Mark the rollback complete only when the baseline evidence is restored. Never fix a route failure with an any-to-any allow.

## Activity 8: Same-VNet variant and asymmetry (optional)

**Goal.** Inspect traffic between two subnets of one VNet and see an asymmetric return path.

**Exam skill.** Explain why a /0 route cannot override VnetLocal and why both directions need a /24 route.

1. **Enable the variant before the first deployment**: Set `enable_same_vnet = true` in the owning `.tfvars`. Changing it later changes the cloud-init data of A and B, so AzureRM can replace those VMs. Save evidence first and review the plan for replacements.

   ```bash
   terraform plan -out=same.tfplan
   terraform show -no-color same.tfplan
   ```

   Expect: The plan adds C, subnet `same-vnet`, `c-nsg`, `c-inspect`, the `same-vnet-forward` route on `app-inspect`, and three firewall rules. It adds no VNet, peering or public IP.

2. **Verify C and run the same-VNet probes**: Open a Bastion session to C, check both listeners, then probe in the order A, A, C, A.

   ```bash
   C_ID=$(terraform output -raw c_vm_id)
   az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$C_ID" \
     --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
   # in C: sudo /usr/local/bin/ew-ready
   /usr/local/bin/ew-probe same-positive            # in A
   /usr/local/bin/ew-probe same-alternate-port      # in A
   /usr/local/bin/ew-probe same-reverse-new         # in C
   /usr/local/bin/ew-probe same-positive            # in A again
   ```

   Expect: Positive: JSON role `c`, `peer_ip=10.10.1.10`, `server_ip=10.10.2.20`. The other two are denied by `deny-same-vnet-alternate-port` and `deny-same-vnet-reverse-new` in the log. A source-preserving response alone proves nothing, because a direct same-VNet path also keeps the source.

3. **Asymmetry experiment and restore (optional)**: Keep C enabled and remove only C's return /24. This is an asymmetric-routing experiment, not a deny test, so record what happens and do not call any one curl result proof.

   ```bash
   terraform plan -var 'same_vnet_return_route_enabled=false' -out=asym.tfplan
   terraform show -no-color asym.tfplan
   # afterwards restore: same_vnet_return_route_enabled=true, then plan and apply again
   ```

   Expect: The plan removes only `same-vnet-return` from `c-inspect`. C's next hop toward A becomes VnetLocal. Restore the route, re-collect both next hops and repeat all four C probes.

## Activity 9: Destroy and verify

**Goal.** Remove everything the lab built and prove it is gone.

**Exam skill.** Know that stopping VMs is not clean-up and that the firewall and Bastion bill until deleted.

1. **Save the evidence first**: Guest evidence lives on the VMs and disappears with them. Copy it through a Bastion tunnel, one VM at a time, with a different local port per VM.

   ```bash
   az network bastion tunnel -g "$RG" -n "$BASTION" --target-resource-id "$APP_ID" \
     --resource-port 22 --port 50022
   # another terminal, preserving host-key checks:
   scp -P 50022 -i "$HOME/.ssh/your-approved-key" -r \
     "$USER_NAME@127.0.0.1:/home/$USER_NAME/ew-evidence" ./evidence/app-guest
   ```

   Expect: Evidence folders for the probes, plus the control-plane output. Redact subscription and tenant identifiers before sharing, and never share state or plan files.

2. **Confirm ownership and preview the destroy**: Check the state and subscription, and that the resource group contains only this lab.

   ```bash
   RG=$(terraform output -raw resource_group_name)
   terraform plan -destroy -out=destroy.tfplan
   terraform show -no-color destroy.tfplan
   ```

   Expect: Only the lab's own resources are listed. The resource-group deletion guard stays on.

3. **Destroy and verify**: After deletion is approved. Include C if you enabled it.

   ```bash
   terraform apply destroy.tfplan
   terraform state list
   az group exists --name "$RG"
   ```

   Expect: An empty state and `false`, only after all deletion completes. Billing views can lag. Stopping the VMs is not clean-up: the firewall and Bastion keep billing until deleted.
