#!/usr/bin/env bash
# Static check of the lab files. Designed, not tested against Azure: it only reads local files.
# Whitespace-tolerant on purpose, so `terraform fmt` realigning '=' never breaks it.
# Usage: ./scripts/check-lab.sh   (run from the terraform folder or anywhere)
set -u
cd "$(dirname "$0")/.."
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# every gate and acknowledgement defaults to false
for v in deploy_firewall accept_firewall_cost deploy_analytics deploy_policy_audit child_allow_blocked_range ipg_app_a_missing_prefix child_conflicting_dnat; do
  if awk -v v="$v" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" v "\"" {inblk=1}
    inblk && $0 ~ /^[[:space:]]*default[[:space:]]*=[[:space:]]*false[[:space:]]*$/ {found=1}
    inblk && $0 ~ /^}/ {inblk=0}
    END {exit found ? 0 : 1}' variables.tf; then ok "switch $v defaults to false"; else bad "switch $v does not default to false"; fi
done

# the association switch defaults to true (so the normal state is associated)
if awk '
    $0 ~ /^[[:space:]]*variable[[:space:]]+"associate_policy_to_firewall"/ {inblk=1}
    inblk && $0 ~ /^[[:space:]]*default[[:space:]]*=[[:space:]]*true[[:space:]]*$/ {found=1}
    inblk && $0 ~ /^}/ {inblk=0}
    END {exit found ? 0 : 1}' variables.tf; then ok "associate_policy_to_firewall defaults to true"; else bad "associate_policy_to_firewall default is wrong"; fi

# the firewall needs both switches and is counted by firewall_on
if grep -Eq 'firewall_on[[:space:]]*=[[:space:]]*var\.deploy_firewall[[:space:]]*&&[[:space:]]*var\.accept_firewall_cost' main.tf; then ok "firewall needs both switches"; else bad "firewall_on does not need both switches"; fi
if grep -Eq 'count[[:space:]]*=[[:space:]]*local\.firewall_on' firewall.tf; then ok "firewall is counted by firewall_on"; else bad "firewall is not gated"; fi

# the cost warnings are prominent
if grep -Eiq 'COST WARNING' variables.tf && grep -Eiq 'COSTLY' variables.tf; then ok "cost warnings present"; else bad "cost warnings missing"; fi

# the firewall subnet name is exact
if grep -Eq 'name[[:space:]]*=[[:space:]]*"AzureFirewallSubnet"' firewall.tf; then ok "subnet is named AzureFirewallSubnet"; else bad "firewall subnet name is wrong"; fi

# children inherit from the parent
n=$(grep -Ec 'base_policy_id[[:space:]]*=[[:space:]]*azurerm_firewall_policy\.parent\.id' policies.tf)
if [ "$n" -ge 2 ]; then ok "two child policies set base_policy_id"; else bad "child policies do not both set base_policy_id"; fi

# rules use IP groups
if grep -Eq 'source_ip_groups[[:space:]]*=' policies.tf && grep -Eq 'destination_ip_groups[[:space:]]*=' policies.tf; then ok "rules reference IP groups"; else bad "rules do not reference IP groups"; fi

# the helper is read-only: no create, delete, update or set verbs
if grep -En 'az[[:space:]].*[[:space:]](create|delete|update|set)([[:space:]]|$)' scripts/policy-check.sh; then bad "policy-check.sh is not read-only"; else ok "policy-check.sh is read-only"; fi

# the audit policy uses effect audit and not deny
if grep -Eq 'effect[[:space:]]*=[[:space:]]*"audit"' governance.tf && ! grep -Eq 'effect[[:space:]]*=[[:space:]]*"deny"' governance.tf; then ok "azure policy effect is audit"; else bad "azure policy effect is not audit"; fi
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
