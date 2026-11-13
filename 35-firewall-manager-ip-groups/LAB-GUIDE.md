# Lab guide: Azure Firewall Manager, policy inheritance and IP groups

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script. The Azure Firewall is costly and is behind a gate that defaults to `false`; policies, rule collection groups and IP groups are free objects as understood here (check current pricing).

## Activity 1: Plan the free baseline: IP groups and the parent policy

**Goal.** Create the five IP groups, the parent policy and its three rule collection groups for free, then read the IP groups and the policy structure.

**Exam skill:** Know that policies, rule collection groups and IP groups are separate objects, and read the prefixes of an IP group.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds a resource group, five IP groups, three policies, and the rule collection groups of each. No firewall, no VNet, no workspace. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. Nothing in the baseline bills by the hour (check current pricing).

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The outputs `parent_policy_id` and `ip_group_ids` are filled; `firewall_public_ip` is empty.

3. **Read the IP groups**

   ```bash
   az network ip-group list -g fm35-rg --query "[].{name:name, cidrs:ipAddresses}" -o json
   ```

   Expect: Five groups. `fm35-ipg-app-a` holds 10.61.1.0/24 and 10.61.2.0/24; `fm35-ipg-blocked` holds 198.51.100.0/24.

4. **Read the parent's groups**

   ```bash
   az network firewall policy rule-collection-group list -g fm35-rg --policy-name fm35-fp-parent --query "[].{group:name, priority:priority}" -o table
   ```

   Expect: Three groups with priorities 100, 200 and 300.

5. **Checkpoint**: Where is the address 10.61.0.0/16 stored, and how many rules refer to it? Answer: once, in `fm35-ipg-spokes`; the parent's deny, DNS and HTTPS rules and application rule all point to it by name.

## Activity 2: Read the rule structure and the priorities

**Goal.** Walk down one rule collection group to its collections and rules, and see priorities at both levels.

**Exam skill:** Name the four levels of a policy and say which one the log row shows.

1. **Show one group in full**

   ```bash
   az network firewall policy rule-collection-group show -g fm35-rg --policy-name fm35-fp-parent -n rcg-200-central-network -o json
   ```

   Expect: A group with priority 200 and two network rule collections, `nc-central-deny` (priority 100, Deny) and `nc-central-allow` (priority 200, Allow).

2. **Find the deny rule**

   ```bash
   az network firewall policy rule-collection-group show -g fm35-rg --policy-name fm35-fp-parent -n rcg-200-central-network --query "ruleCollections[0].rules[].{rule:name, src:sourceIpGroups, dst:destinationIpGroups}" -o json
   ```

   Expect: The rule `deny-known-bad` refers to the IP groups by resource id, not by address.

3. **Read the DNAT group**

   ```bash
   az network firewall policy rule-collection-group show -g fm35-rg --policy-name fm35-fp-parent -n rcg-100-central-dnat -o json
   ```

   Expect: A NAT collection with one rule: 203.0.113.10:443 to 10.60.8.10:443.

4. **Checkpoint**: In which order would the firewall read the three parent groups, and inside group 200 which collection is first? Answer: 100, 200, 300; inside group 200 both are network collections, so by priority: the deny collection (100) before the allow collection (200).

## Activity 3: Create the child policies and read the inheritance

**Goal.** See that child A and child B name the parent as their base, and that the parent lists its children.

**Exam skill:** Explain inheritance: what the child receives, and who edits what.

1. **Read the parent's children**

   ```bash
   az network firewall policy show -g fm35-rg -n fm35-fp-parent --query "{name:name, children:childPolicies[].id}" -o json
   ```

   Expect: Two child ids: `fm35-fp-child-a` and `fm35-fp-child-b`.

2. **Read each child's base**

   ```bash
   az network firewall policy show -g fm35-rg -n fm35-fp-child-a --query "{name:name, base:basePolicy.id}" -o json
   ```

   Expect: `base` is the id of `fm35-fp-parent`. Repeat for `fm35-fp-child-b`.

3. **List the child's own groups**: The command lists only the child's own groups; the inherited ones are shown in the portal as read-only.

   ```bash
   az network firewall policy rule-collection-group list -g fm35-rg --policy-name fm35-fp-child-a --query "[].{group:name, priority:priority}" -o table
   ```

   Expect: One group, `rcg-100-app-a`, priority 100.

4. **Portal check**: In the portal open Firewall Manager, Azure Firewall Policies, `fm35-fp-child-a`, Rule collections. The parent's groups appear as inherited and cannot be edited.

5. **Checkpoint**: The child group has priority 100 and the parent's DNAT group also has 100. Which is read first? Answer: the parent's, because the parent is read first regardless of numbers.

## Activity 4: Edit an IP group and see the reuse

**Goal.** Remove and restore a prefix in one IP group, and see which policies reference it.

**Exam skill:** Use the IP group as the single place for an address list, and find what an edit affects.

1. **See where an IP group is used**

   ```bash
   az network ip-group show -g fm35-rg -n fm35-ipg-shared --query "{cidrs:ipAddresses, policies:firewallPolicies[].id, firewalls:firewalls[].id}" -o json
   ```

   Expect: The `policies` list shows the policies whose rules reference the group; `firewalls` is empty without gate 1. (The property names may differ: check current docs.)

2. **Remove the new subnet on purpose**: This is also break/fix 2. Set `ipg_app_a_missing_prefix = true` in `terraform.tfvars`.

   ```bash
   terraform plan -out=ipg.tfplan
   terraform apply ipg.tfplan
   ```

   Expect: The plan changes only `fm35-ipg-app-a`. No rule is changed.

3. **Read the group again**

   ```bash
   az network ip-group show -g fm35-rg -n fm35-ipg-app-a --query ipAddresses -o json
   ```

   Expect: Only 10.61.1.0/24 is left.

4. **Restore it**: Set the switch back to `false`, plan and apply. One edit restores every rule that uses the group.

   Expect: The group has both prefixes again.

5. **Checkpoint**: You changed one object and the rules followed. How many rules would you have edited with inline addresses? Answer: every rule that listed the subnet, in every policy, one by one.

## Activity 5: Compare the settings of parent and children, and audit with Azure Policy

**Goal.** Read DNS, threat intelligence and IDPS settings on all three policies, then turn on the audit assignment.

**Exam skill:** Verify the effective setting of a child, and know that Azure Policy audits association but not rule content.

1. **Read the settings**

   ```bash
   ./scripts/policy-check.sh settings
   ```

   Expect: Parent: DNS proxy enabled, threat intelligence Alert. Child A has no value of its own: the helper shows what the API returns, and the portal shows the inherited value. Child B: threat intelligence Deny. IDPS is empty unless `policy_sku = "Premium"`.

2. **Turn on the audit gate**: Set `deploy_policy_audit = true`. It creates a custom definition and an `audit` assignment on the lab resource group. Nothing is denied or changed.

   ```bash
   terraform plan -out=audit.tfplan
   terraform apply audit.tfplan
   ```

   Expect: Two new objects: a policy definition and a resource group assignment.

3. **Read the compliance**: Compliance results can take some time to appear. Without gate 1 there are no firewalls, so the result is empty.

   ```bash
   ./scripts/policy-check.sh audit
   ```

   Expect: Empty without a firewall. With gate 1, a firewall that uses an approved policy is compliant and one without a policy is not.

4. **Checkpoint**: Child B sets threat intelligence to Deny and child A sets nothing. What does a firewall using child A get? Answer: the parent's Alert, by inheritance. Verify it in the portal.

## Activity 6: Add the firewall (gate 1, costly), the association and the logs

**Goal.** Create one Azure Firewall, associate it with child A, read the association and the first log rows.

**Exam skill:** Know that the association is a property of the firewall, and that logs name the policy and rule.

1. **Open gate 1 and, optionally, gate 2**: Set `deploy_firewall = true` AND `accept_firewall_cost = true`. Azure Firewall bills per hour from creation: read `grep -n COST variables.tf` first and destroy it in the same sitting. Optionally set `deploy_analytics = true` for the workspace and the diagnostic setting.

   ```bash
   terraform plan -out=firewall.tfplan
   terraform apply firewall.tfplan
   ```

   Expect: A hub VNet, the AzureFirewallSubnet, a public IP and the firewall, with child A as its policy. Creation takes several minutes.

2. **Read the association**

   ```bash
   ./scripts/policy-check.sh firewall
   ```

   Expect: `policy` is the id of `fm35-fp-child-a`. The `provisioningState` is Succeeded after the update.

3. **Read the policy's view**

   ```bash
   az network firewall policy show -g fm35-rg -n fm35-fp-child-a --query firewalls[].id -o json
   ```

   Expect: The firewall id is listed under the child policy.

4. **Optional: query the logs**: Needs gate 2 and some traffic. Without workloads in spokes there is little to see: run the queries in `queries/firewall-policy-queries.kql` in the workspace, and check the table names in your own workspace.

   Expect: Rows with the Policy column once traffic flows. Ingestion can take minutes.

5. **Checkpoint**: Where is the diagnostic setting and where is the policy name in the log? Answer: the diagnostic setting is on the firewall; the policy name is a column in each row.

## Activity 7: Run the four break/fix drills

**Goal.** Cause each of the four failures with a variable, diagnose it from the objects and logs, and fix it.

**Exam skill:** Diagnose from the policy order, the IP group, the association and the DNAT list, without guessing.

1. **Case 1: shadowed child rule**: Set `child_allow_blocked_range = true`, plan and apply. The child now has an allow for 198.51.100.0/24 that the parent denies first.

   ```bash
   terraform plan -out=bf1.tfplan
   terraform apply bf1.tfplan
   ./scripts/policy-check.sh groups
   ```

   Expect: Child A has a second collection, but the parent's deny is read first. With gate 1 and traffic, the log shows the parent's rule. Set the switch back to `false`.

2. **Case 2: IP group missing a prefix**: Set `ipg_app_a_missing_prefix = true` and apply. Check the group with `./scripts/policy-check.sh ipgroups`.

   Expect: `fm35-ipg-app-a` lacks 10.61.2.0/24. Restore it.

3. **Case 3: policy not associated**: Needs gate 1. Set `associate_policy_to_firewall = false` and apply.

   ```bash
   ./scripts/policy-check.sh firewall
   ```

   Expect: `policy` is empty. Restore the switch.

4. **Case 4: conflicting DNAT**: Set `child_conflicting_dnat = true` and apply. The portal or the API may reject the overlap or accept it (hedge: check current behaviour).

   ```bash
   ./scripts/policy-check.sh groups
   ```

   Expect: A second DNAT rule for 203.0.113.10:443 exists in child A. The parent's DNAT is read first. Restore the switch.

5. **Checkpoint**: For each case, name the first command you ran and what it showed. Answer: groups (order), ipgroups (prefixes), firewall (association), groups (DNAT in both policies).

## Activity 8: Static check, paper review and destroy

**Goal.** Check the lab files without Azure, review a change on paper, and destroy the lab.

**Exam skill:** Review a policy change like code, and clean up the costly stages first.

1. **Run the static check**: It reads only local files and ignores whitespace, so `terraform fmt` never breaks it.

   ```bash
   ./scripts/check-lab.sh
   ```

   Expect: Every line starts with `ok` and the last line is `ALL CHECKS PASSED`.

2. **Paper review**: Imagine adding a rule to the parent that denies tcp/1433 to ipg-shared. List every child and firewall affected, the canary you would use and the rollback. Use `./scripts/policy-check.sh parent` and `ipgroups` for the lists.

   Expect: Both children and every firewall that uses them are affected, so the canary is a non-production firewall on a copy of the parent.

3. **Destroy the costly stages first**: Set the gate variables to `false` and apply, or destroy through your own workflow. Delete the firewall before anything else.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: The firewall, its public IP, the hub VNet and the workspace go. Then the free objects.

4. **Confirm nothing is left**

   ```bash
   az resource list -g fm35-rg -o table
   ```

   Expect: The resource group is empty or gone. Check the portal for orphaned public IPs.
