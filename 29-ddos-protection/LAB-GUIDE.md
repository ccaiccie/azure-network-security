# Lab guide: Azure DDoS Protection (defensive only)

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. **COST WARNING: a DDoS protection plan (gate 3) costs roughly thousands of US dollars per month and IP Protection (gate 4) costs a few hundred per IP per month; both are approximate, so check current Azure pricing.** The lab never generates traffic and contains no attack tooling; real tests go only through a Microsoft-approved simulation partner. Addresses are RFC 5737 documentation examples; yours will differ. Check current Microsoft docs for features, limits, metric and log category names and provider attribute names.

## Activity 1: Plan the free baseline and read the platform default

**Goal.** Create the free network objects and see that, with no plan, a VNet has only the always-on platform protection.

**Exam skill:** Know that infrastructure protection is on for every public IP by default, free, with no tuning or telemetry, and that a VNet records its plan link in `ddosProtectionPlan`.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds a resource group, a VNet, one subnet, one NSG, its rules and its association. No public IP, no VM, no plan. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. Nothing in the baseline bills by the hour.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The outputs `ddos_plan_id` and `public_ip_web` are empty.

3. **Read the VNet's DDoS fields**

   ```bash
   az network vnet show -g ddos29-rg -n ddos29-vnet --query "{plan:ddosProtectionPlan.id, enabled:enableDdosProtection}" -o json
   ```

   Expect: `plan` is null and `enabled` is false: only the platform baseline applies.

4. **Checkpoint**: What protects a public IP in this VNet today? Answer: nothing you configured. Azure's infrastructure protection guards the platform for every customer, but it is not tuned to your address and gives you no metrics or logs.

## Activity 2: Add the workload and read the public IP settings

**Goal.** Open gate 1 to create one VM with a public IP, and a second public IP that is attached to nothing. Read the DDoS setting on both.

**Exam skill:** Know that a public IP has a protection mode (Enabled, Disabled or VirtualNetworkInherited), that Inherited only helps when the IP sits behind a resource in a linked VNet, and that an unattached IP has nothing to inherit from.

1. **Open gate 1**: Set `deploy_workload = true` and paste your public key text into `admin_ssh_public_key`. The VM has no SSH rule; the lab uses run-command.

   ```bash
   terraform plan -out=workload.tfplan
   terraform apply workload.tfplan
   ```

   Expect: Two Standard public IPs, one NIC, one small Linux VM. Small hourly cost for the VM and the IPs.

2. **Read both public IPs**

   ```bash
   az network public-ip list -g ddos29-rg --query "[].{name:name, sku:sku.name, mode:ddosSettings.protectionMode, attached:ipConfiguration.id}" -o table
   ```

   Expect: `ddos29-pip-web` is attached to the NIC; `ddos29-pip-spare` shows an empty `attached` column. Both show `VirtualNetworkInherited` or an empty mode (the default).

3. **Check the web page answers**: A normal single request from your own machine. This is not a test of protection.

   ```bash
   curl -I http://<pip-web address>
   ```

   Expect: HTTP 200 from nginx. If it hangs, read the NSG rules on `snet-web`.

4. **Checkpoint**: Which of the two IPs could ever be covered by a plan, and why? Answer: pip-web, once its VNet is linked; pip-spare is attached to nothing, so there is no VNet to inherit from.

## Activity 3: Turn on diagnostics and the attack alert

**Goal.** Open gate 2 to create a workspace, a diagnostic setting on pip-web, an action group and a metric alert on the under attack metric.

**Exam skill:** Know the three DDoS log categories, that a diagnostic setting is per resource, and that an alert needs the right scope, signal and receiver.

1. **Open gate 2**: Set `deploy_monitoring = true` and `alert_email` to an address you control (the example default is a documentation address that nobody reads).

   ```bash
   terraform plan -out=mon.tfplan
   terraform apply mon.tfplan
   ```

   Expect: A workspace, an action group, a diagnostic setting, and a metric alert. Small ingestion cost.

2. **List the diagnostic setting**

   ```bash
   az monitor diagnostic-settings list --resource $(az network public-ip show -g ddos29-rg -n ddos29-pip-web --query id -o tsv) --query "value[].{name:name, logs:logs[].category, workspace:workspaceId}" -o json
   ```

   Expect: The categories `DDoSProtectionNotifications`, `DDoSMitigationFlowLogs` and `DDoSMitigationReports`, plus the metrics, all sent to the workspace. (Category names: check current docs.)

3. **List the metric definitions**: Without a protected IP the DDoS metrics may be absent or empty. Read what exists.

   ```bash
   az monitor metrics list-definitions --resource $(az network public-ip show -g ddos29-rg -n ddos29-pip-web --query id -o tsv) --query "[].name.value" -o tsv
   ```

   Expect: Basic metrics such as byte and packet counts. The DDoS metrics appear once protection is on (Activity 4 or 5). Metric names: check current docs.

4. **Read the alert rule**

   ```bash
   az monitor metrics alert show -g ddos29-rg -n ddos29-under-attack --query "{scopes:scopes, criteria:criteria.allOf[0].metricName, enabled:enabled}" -o json
   ```

   Expect: The scope is pip-web, the signal is the under attack metric, `enabled` is true.

5. **Checkpoint**: Why is the alert scoped to the public IP and not to the VNet? Answer: the DDoS metrics belong to each public IP resource, so a rule scoped to the VNet has nothing to evaluate.

## Activity 4: Create the plan, link the VNet (costly)

**Goal.** Open gate 3 to create a DDoS protection plan and link the VNet. Read which IPs are covered and which are not.

**Exam skill:** Know that Network Protection is a plan linked to VNets, that coverage follows the public IP's resource and VNet, and that the plan is billed at a high monthly rate from creation. Check current Microsoft docs for the price.

1. **Read the cost warning first**: A DDoS protection plan costs roughly thousands of US dollars per month (check current pricing). Do this only in a subscription where that is acceptable, and plan to destroy it in the same sitting. The lab needs two switches so that one typo cannot create it.

   ```bash
   grep -n "accept_ddos_plan_cost" variables.tf
   ```

   Expect: The variable defaults to `false` and its description starts with a cost warning.

2. **Open gate 3 with the acknowledgement**: Set both `deploy_ddos_network_protection = true` and `accept_ddos_plan_cost = true`. Leave `deploy_ip_protection = false`.

   ```bash
   terraform plan -out=plan.tfplan
   terraform apply plan.tfplan
   ```

   Expect: One plan, and the VNet now has a `ddos_protection_plan` block with `enable = true`.

3. **Read the link from both sides**

   ```bash
   az network vnet show -g ddos29-rg -n ddos29-vnet --query "{plan:ddosProtectionPlan.id, enabled:enableDdosProtection}" -o json
   az network ddos-protection show -g ddos29-rg -n ddos29-plan --query "virtualNetworks[].id" -o tsv
   ```

   Expect: The VNet shows the plan id and `enabled` true; the plan lists the VNet.

4. **Compare the two IPs**: pip-web is behind a VM in the linked VNet. pip-spare is attached to nothing.

   ```bash
   az network public-ip list -g ddos29-rg --query "[].{name:name, mode:ddosSettings.protectionMode}" -o table
   ```

   Expect: Both show the same inherited mode. Only pip-web is really covered. The mode string does not tell you coverage; the VNet link and the attachment do.

5. **Checkpoint**: pip-spare shows the same mode as pip-web. Is it protected? Answer: no, there is no VNet to inherit from. Attach it to a resource in a linked VNet, or enable IP Protection on it.

## Activity 5: Try IP Protection instead (costly, alternative to Activity 4)

**Goal.** Remove the plan and switch on IP Protection for pip-web only. See how coverage is read from the IP itself.

**Exam skill:** Know that IP Protection is set per public IP, needs no plan and no VNet link, and is billed per protected IP. Know the extras that stay with Network Protection (check current docs).

1. **Close gate 3**: Set `deploy_ddos_network_protection = false` and `accept_ddos_plan_cost = false`, then set `deploy_ip_protection = true`. The lab refuses both tiers at once.

   ```bash
   terraform plan -out=ip.tfplan
   terraform apply ip.tfplan
   ```

   Expect: The plan is destroyed, the VNet link is removed, and pip-web changes to `Enabled`. If Azure refuses to delete the plan while the VNet is still linked, apply once with `link_vnet_to_plan = false` first, then close gate 3.

2. **Read the IP**

   ```bash
   az network public-ip show -g ddos29-rg -n ddos29-pip-web --query "{mode:ddosSettings.protectionMode, plan:ddosSettings.ddosProtectionPlan.id}" -o json
   ```

   Expect: `mode` is `Enabled` and `plan` is null: that is IP Protection.

3. **Compare the cost model**: Write down the per-IP price and the monthly plan price from the current pricing page and compute the break-even number of IPs. At roughly 15 protected IPs the plan can become cheaper, but recompute with current prices and add the extras.

   ```bash
   # paper exercise: plan price / per-IP price = break-even number of IPs
   ```

   Expect: A number you can defend in a design review.

4. **Checkpoint**: What do you lose by choosing IP Protection? Answer: some Network Protection extras, such as DDoS Rapid Response, cost protection and the WAF discount. Verify the current list in Microsoft docs.

## Activity 6: Read the telemetry and test the alert path

**Goal.** Look at the metrics and queries that will answer questions during an attack, and prove that the action group delivers a message.

**Exam skill:** Know the under attack metric, the dropped and forwarded packet metrics, the three log categories, and how to test a receiver without an attack.

1. **List the metrics now that protection is on**

   ```bash
   az monitor metrics list-definitions --resource $(az network public-ip show -g ddos29-rg -n ddos29-pip-web --query id -o tsv) --query "[?contains(name.value, 'DDoS')].name.value" -o tsv
   ```

   Expect: Several names containing `DDoS`, such as the under attack metric and packets dropped or forwarded. (Exact names: check current docs.)

2. **Chart the under attack metric**: Read the metric for the last hour. It is expected to be 0 or empty: nothing attacks the lab.

   ```bash
   az monitor metrics list --resource $(az network public-ip show -g ddos29-rg -n ddos29-pip-web --query id -o tsv) --metric IfUnderDDoSAttack --interval PT5M --aggregation Maximum -o table
   ```

   Expect: Values of 0, or no data. A flat zero is the healthy answer.

3. **Send a test notification**: In the portal open the action group and use Test action group. No attack is needed and none is generated.

   ```bash
   # portal: Monitor > Alerts > Action groups > ddos29-ag > Test
   ```

   Expect: The email arrives. If it does not, fix the receiver before you trust the alert.

4. **Run the saved queries**: Open `queries/ddos-queries.kql` in the workspace. They return nothing in a quiet lab. That is the point: you now know the queries work and where to look.

   ```bash
   ./scripts/ddos-check.sh queries
   ```

   Expect: The script prints the file path and the three categories.

5. **Checkpoint**: Which log category tells you an attack started, which one lists dropped flows, and which one summarises the attack? Answer: notifications, mitigation flow logs and mitigation reports.

## Activity 7: Break/fix drills with the lab's own switches

**Goal.** Cause three of the break/fix cases from Terraform variables, find each one with read-only commands, and undo it.

**Exam skill:** Diagnose 'no protection' from settings, not from guesses: the VNet link, the IP's mode and attachment, the diagnostic setting, and the alert scope.

1. **Drill 1: unlink the VNet**: Re-enable gate 3 with the acknowledgement, then set `link_vnet_to_plan = false` and apply.

   ```bash
   terraform apply
   ./scripts/ddos-check.sh tier
   ```

   Expect: The plan exists but the VNet's `ddosProtectionPlan` is null. The plan costs money and protects nothing. Set the variable back to `true`.

2. **Drill 2: disable the IP**: Set `pip_web_mode_override = "Disabled"` and apply.

   ```bash
   terraform apply
   ./scripts/ddos-check.sh ip
   ```

   Expect: pip-web shows `Disabled`. Clear the override (empty string) afterwards. (Disabled and plan behaviour: check current docs.)

3. **Drill 3: aim the alert at the wrong IP**: Set `alert_on_spare_ip_by_mistake = true` and apply.

   ```bash
   terraform apply
   ./scripts/ddos-check.sh alerts
   ```

   Expect: The rule's scope is pip-spare, an address that is not protected and never emits the metric. The alert can never fire. Set the variable back to `false`.

4. **Checkpoint**: Which of the three drills still produced mitigation, and which produced telemetry? Answer: drill 3 still mitigates (pip-web is protected) but the alert is blind; drills 1 and 2 remove tuned protection and its telemetry.

## Activity 8: Plan an approved simulation on paper, then clean up

**Goal.** Write the request you would send to an approved simulation partner, without running anything, and then destroy the lab.

**Exam skill:** Know the approved process: Microsoft-approved partners only, your own IPs only, an agreed window and rules, monitoring ready. No traffic is generated in this lab.

1. **Fill the paper checklist**: Copy the checklist into your notes and fill it from the lab: target IP, owner, window, stop condition, expected metrics, who watches, who can stop it, and the partner you would pick from Microsoft's current list.

   ```bash
   # paper exercise, no commands
   ```

   Expect: A complete one-page plan. Nothing is sent and nothing is run.

2. **Check the lab for attack tooling**: The lab contains none. Confirm that nothing in the folder generates traffic.

   ```bash
   ./scripts/check-lab.sh
   ```

   Expect: All checks pass, including 'no traffic generator'.

3. **Destroy the lab**: Close every gate or destroy the whole state. The plan and the IP tier are the costly parts, so confirm them first.

   ```bash
   terraform destroy
   ```

   Expect: `Destroy complete`. Then `az network ddos-protection list -g ddos29-rg` returns nothing.

4. **Checkpoint**: Why can the plan keep billing even after the VM is deleted? Answer: the plan is its own billed resource, independent of what is linked to it. Check that it is gone.
