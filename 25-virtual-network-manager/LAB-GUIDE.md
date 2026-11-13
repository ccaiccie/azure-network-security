# Lab guide: Azure Virtual Network Manager

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses are RFC 1918 examples. Check current Microsoft docs for limits, feature status, pricing and provider argument names, and install the Azure CLI extension `virtual-network-manager` for the `az network manager` commands.

## Activity 1: Plan the free baseline: four VNets and no peering

**Goal.** Create the hub and three spokes (all free) and confirm that, before any manager exists, nothing connects them.

**Exam skill:** Know that VNets are isolated by default, that tags are the raw material for dynamic groups, and that nothing in AVNM changes a VNet until a configuration is committed.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 9 objects: 1 resource group, 4 VNets and 4 subnets. No network manager, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the outputs `resource_group` and `vnet_ids`; `network_manager_name` is empty.

3. **Read the tags**: The `env` tag is what the dynamic group selects on in Activity 5.

   ```bash
   az network vnet list -g avnm25-rg --query "[].{name:name, env:tags.env, role:tags.role}" -o table
   ```

   Expect: hub (role hub, no env), spoke-a prod, spoke-b prod, spoke-c dev.

4. **Confirm there are no peerings**

   ```bash
   ./scripts/avnm-check.sh peerings
   ```

   Expect: Every VNet prints an empty table. Nothing connects them yet.

5. **Checkpoint**: Which tag value keeps spoke-c out of the dynamic group, and why does the hub carry no `env` tag? Answer: `env = dev` does not match the policy's `env = prod` condition; the hub is named in the connectivity configuration, not selected by tag.

## Activity 2: Create the network manager and a static network group

**Goal.** Open gate 1 to create a network manager scoped to your subscription and a static group holding spoke-a and spoke-b.

**Exam skill:** Explain scope (what the manager may touch) versus scope access (which features it may use), and static group membership. Know that creating them changes no VNet.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_avnm = true`.

   ```bash
   terraform plan -out=avnm.tfplan
   terraform apply avnm.tfplan
   ```

   Expect: 4 objects: the network manager, the group `ng-spokes-static` and two static members. (Designed, not tested.) If the apply fails on permissions, check that your account may create network managers and join VNets to groups; check current docs for the exact actions.

2. **Read the manager's scope**: The scope lists the subscription; the scope accesses are Connectivity and SecurityAdmin.

   ```bash
   az network manager show -g avnm25-rg -n avnm25-avnm --query "{scope:networkManagerScopes, access:networkManagerScopeAccesses}" -o json
   ```

   Expect: The subscription id under `subscriptions`, and the two access values. The extension `virtual-network-manager` may need installing first.

3. **List the group members**

   ```bash
   ./scripts/avnm-check.sh groups
   ```

   Expect: spoke-a and spoke-b under ng-spokes-static; the dynamic group does not exist yet.

4. **Confirm that no VNet changed**

   ```bash
   ./scripts/avnm-check.sh peerings
   ```

   Expect: Still empty. A manager and a group are only definitions.

5. **Checkpoint**: The manager's scope is the subscription. Could you create a connectivity configuration for a VNet in another subscription? Answer: only if that subscription (or its management group) is in the scope; otherwise it cannot be a member.

## Activity 3: Hub-and-spoke connectivity, direct connectivity and rollback

**Goal.** Commit configuration v1 (hub-and-spoke), show that spokes cannot reach each other, commit v2 (direct connectivity), then roll back to v1 by deploying it again.

**Exam skill:** Read effective routes to see what a connectivity configuration really did, know that spoke-to-spoke needs direct connectivity or a hub router, and explain rollback as deploying the previous configuration.

1. **Open gates 2 and 5**: Set `deploy_connectivity = true`, `deploy_vms = true`, `admin_ssh_public_key = "<text of your public key>"` and keep `active_connectivity = "v1"`. The VMs bill by the hour.

   ```bash
   terraform plan -out=conn.tfplan
   terraform apply conn.tfplan
   ```

   Expect: Two connectivity configurations, one deployment to westeurope, three VMs with NICs, an NSG and three associations. Peering creation can take several minutes.

2. **Read the peerings AVNM created**

   ```bash
   ./scripts/avnm-check.sh peerings
   ```

   Expect: The hub has one peering per spoke, and each spoke has one to the hub. Spoke-c has none: it is not in the group.

3. **Try spoke-to-spoke under v1**: The helper calls vm-b's web page from vm-a, and vm-c's page.

   ```bash
   ./scripts/avnm-check.sh app
   ```

   Expect: Both calls print `000`: no connection. Under v1 spoke-a has no route to spoke-b, and spoke-c was never connected.

4. **Read the effective routes**

   ```bash
   ./scripts/avnm-check.sh routes
   ```

   Expect: vm-a shows 10.71.0.0/24 VnetLocal, 10.70.0.0/24 through the hub peering and 0.0.0.0/0 Internet. No 10.72.0.0/24.

5. **Commit v2**: Set `active_connectivity = "v2"` and apply. The deployment replaces v1 in westeurope.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh routes
   ./scripts/avnm-check.sh app
   ```

   Expect: vm-a now has a route for 10.72.0.0/24. The call to vm-b prints `200` (the NSG allows 8080 and no admin rule exists yet). The call to vm-c is still `000`.

6. **Roll back**: Set `active_connectivity = "v1"` and apply. This deploys v1 again; nothing is 'undone'.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh app
   ```

   Expect: The call to vm-b prints `000` again. The v2 definition is still in the manager, only no longer committed.

7. **Checkpoint**: Why does v1 not let spoke-a reach spoke-b even though both are peered with the hub? Answer: peering is not transitive, and the hub has no firewall or router to forward the packet. Direct connectivity adds the path.

## Activity 4: Security admin rules against an NSG: the action matrix

**Goal.** Commit a security admin configuration and walk through four combinations of admin action and NSG result to see which layer decides.

**Exam skill:** Predict the outcome for Allow, Deny and Always allow against an NSG allow or deny, and find the deciding rule with effective security rules.

1. **Prepare: commit v2 again and open gate 3**: Set `active_connectivity = "v2"`, `deploy_security_admin = true` and `admin_rule_action = "Deny"`.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh committed
   ```

   Expect: The committed security admin rules list `r-block-mgmt` and `r-app-port` for westeurope. Commit can take a few minutes.

2. **Case 1: admin Deny, NSG allow**

   ```bash
   ./scripts/avnm-check.sh app
   ./scripts/avnm-check.sh rules
   ```

   Expect: The call to vm-b prints `000`. The effective security rules of vm-b-nic list the admin rule `r-app-port` with action Deny, ahead of the NSG rules.

3. **Case 2: admin Allow, NSG allow**: Set `admin_rule_action = "Allow"` and apply (the security deployment is re-committed).

   ```bash
   terraform apply
   ./scripts/avnm-check.sh app
   ```

   Expect: `200`: the admin layer does not object and the NSG allows.

4. **Case 3: admin Allow, NSG deny**: Also set `nsg_allows_app_port = false` and apply.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh app
   ```

   Expect: `000`: the NSG has the last word when the admin action is Allow.

5. **Case 4: admin Always allow, NSG deny**: Set `admin_rule_action = "AlwaysAllow"` and apply.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh app
   ```

   Expect: `200`: Always allow skips the NSG although it denies the port.

6. **Restore and check the guardrail**: Set `admin_rule_action = "Deny"` back, `nsg_allows_app_port = true`, and apply. The rule `r-block-mgmt` has denied TCP 22 and 3389 from the Internet service tag throughout; the lab VMs have no public IP, so you cannot test it from outside.

   ```bash
   terraform apply
   ```

   Expect: The plan shows only the rule action and the NSG rule changing.

7. **Checkpoint**: An application team opens port 8080 in the NSG, but the platform team has a Deny admin rule for it. Who wins, and what does the application team see? Answer: the admin rule wins; the NSG shows an allow but the client times out. Effective security rules on the NIC show the admin rule.

## Activity 5: Dynamic membership with Azure Policy

**Goal.** Open gate 4 so that an Azure Policy fills a second network group from tags, then change a tag and watch the membership follow.

**Exam skill:** Explain how dynamic membership works (policy effect addToNetworkGroup), why it is not instant, and that being in a group does nothing until a configuration targets that group.

1. **Open gate 4**: Set `deploy_dynamic_group = true`. This creates a custom policy definition and a subscription-level assignment, so use a sandbox subscription.

   ```bash
   terraform plan -out=dyn.tfplan
   terraform apply dyn.tfplan
   ```

   Expect: 4 objects: the group `ng-prod-dynamic`, the policy definition, the assignment and nothing else. (Designed, not tested.) The policy mode `Microsoft.Network.Data` and the effect must be checked against current docs.

2. **Wait, then read the members**: Policy evaluation is not instant. Trigger a scan if you do not want to wait.

   ```bash
   az policy state trigger-scan -g avnm25-rg
   ./scripts/avnm-check.sh groups
   ```

   Expect: After the scan, ng-prod-dynamic lists spoke-a and spoke-b (env = prod). spoke-c (env = dev) and the hub are absent. The delay can be minutes; check current docs.

3. **Change a tag through Terraform**: Set `spoke_c_env = "prod"` and apply, then scan again.

   ```bash
   terraform apply
   az policy state trigger-scan -g avnm25-rg
   ./scripts/avnm-check.sh groups
   ```

   Expect: spoke-c joins the dynamic group after the next evaluation.

4. **Check that nothing else changed**

   ```bash
   ./scripts/avnm-check.sh peerings
   ```

   Expect: spoke-c still has no peering: no configuration targets the dynamic group. Membership is only the list.

5. **Checkpoint**: Name two reasons a VNet you tagged env = prod might be missing from the dynamic group. Answer: the policy has not evaluated yet, or the VNet is outside the policy assignment or the manager's scope (also: a tag key or value that differs in spelling).

## Activity 6: Regional deployments: the uncovered spoke

**Goal.** Add spoke-d in a second region and see that it stays unconnected until that region is part of the deployment.

**Exam skill:** Remember that a deployment is per region, find a missing region by reading what is committed, and fix it by adding the region.

1. **Open gate 6**: Set `deploy_second_region = true` (spoke-d is a free VNet in northeurope; it joins the static group). Keep `deployment_regions = ["westeurope"]`.

   ```bash
   terraform apply
   ```

   Expect: A second resource group, VNet and subnet, and a static member for spoke-d.

2. **See that spoke-d is not covered**

   ```bash
   ./scripts/avnm-check.sh peerings
   ```

   Expect: spoke-d has no peering to the hub although it is a member of the group. The configuration is only committed to westeurope.

3. **Add the region**: Set `deployment_regions = ["westeurope", "northeurope"]` and apply. This adds a deployment per scope access in the new region.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh committed
   ```

   Expect: The committed lists now include northeurope, and spoke-d has a peering to the hub (cross-region, so global peering).

4. **Checkpoint**: The group lists spoke-d as a member, the configuration is deployed, and yet it has no peering. What do you check? Answer: whether the region of spoke-d is among the deployed regions of that scope access.

## Activity 7: Portal tour of routing, IPAM and the verifier, then clean up

**Goal.** Look at the three features the lab does not build (routing configuration, IPAM pools, verifier), then remove the lab.

**Exam skill:** Describe what each of the three features does, know that they are hedged in this guide (status and limits change), and clean up in the right order: commit nothing, delete deployments, then destroy.

1. **Open the network manager in the portal**: Read-only. Look at the Configurations, Network groups and Deployments pages and note the deployment status per region.

   ```bash
   az network manager list -g avnm25-rg -o table
   ```

   Expect: One manager. Use the portal pages to see the committed configurations and regions.

2. **Look at routing configuration, IPAM and verifier**: These are not in the Terraform lab: provider support and service status (preview or GA) change, so check current Microsoft docs. In the portal find Configurations (Routing), IP address pools and Verifier workspaces if your scope access and region offer them.

   Expect: You should be able to say, for each, which problem it solves and which part of the picture it does not cover. Do not create anything unless you want to.

3. **Clean up in reverse order**: In `terraform.tfvars` set `deploy_vms`, `deploy_dynamic_group`, `deploy_security_admin`, `deploy_connectivity`, `deploy_second_region` and `deploy_avnm` to `false`, in that order if the apply complains about dependencies. Removing a deployment resource should remove the commit; check the provider documentation for what a destroy does.

   ```bash
   terraform apply
   ./scripts/avnm-check.sh peerings
   ```

   Expect: The managed peerings are gone and the manager is deleted. If a configuration cannot be deleted, remove its deployment first in the portal.

4. **Destroy the rest**: Only after the gates are closed.

   ```bash
   terraform destroy
   ```

   Expect: The resource groups and VNets are removed. Public IPs were never created in this lab.

5. **Checkpoint**: Why delete deployments before configurations? Answer: a committed configuration is in use on VNets; removing the deployment removes its effect first, and then the definition can be deleted.
