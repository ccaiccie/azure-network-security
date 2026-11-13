#!/usr/bin/env bash
# Static check of the lab files. Designed, not tested against Azure: it only reads local files.
# Whitespace-tolerant on purpose, so `terraform fmt` realigning '=' never breaks it.
# Usage: ./scripts/check-lab.sh   (run from the terraform folder)
set -u
cd "$(dirname "$0")/.."
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# every gate and acknowledgement defaults to false
for v in deploy_workload deploy_bastion accept_bastion_cost deploy_defender_servers accept_defender_cost vm_public_ip; do
  if awk -v v="$v" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" v "\"" {inblk=1}
    inblk && $0 ~ /^[[:space:]]*default[[:space:]]*=[[:space:]]*false[[:space:]]*$/ {found=1}
    inblk && $0 ~ /^}/ {inblk=0}
    END {exit found ? 0 : 1}' variables.tf; then ok "gate $v defaults to false"; else bad "gate $v does not default to false"; fi
done

# the costly stages need both switches
if grep -Eq 'bastion_on[[:space:]]*=[[:space:]]*var\.deploy_bastion[[:space:]]*&&[[:space:]]*var\.accept_bastion_cost' main.tf; then ok "bastion needs both switches"; else bad "bastion_on does not need both switches"; fi
if grep -Eq 'defender_on[[:space:]]*=[[:space:]]*var\.deploy_defender_servers[[:space:]]*&&[[:space:]]*var\.accept_defender_cost' main.tf; then ok "defender needs both switches"; else bad "defender_on does not need both switches"; fi
if grep -Eq 'count[[:space:]]*=[[:space:]]*local\.bastion_on' bastion.tf; then ok "bastion host is counted by bastion_on"; else bad "bastion host is not gated"; fi
if grep -Eq 'count[[:space:]]*=[[:space:]]*local\.defender_on' defender.tf; then ok "defender plan is counted by defender_on"; else bad "defender plan is not gated"; fi

# the cost warnings are prominent
if grep -Eiq 'COST WARNING' variables.tf && grep -Eiq 'COSTLY' variables.tf && grep -Eiq 'SUBSCRIPTION-WIDE' variables.tf; then ok "cost warnings present"; else bad "cost warnings missing"; fi

# the Bastion subnet name is exact
if grep -Eq 'name[[:space:]]*=[[:space:]]*"AzureBastionSubnet"' main.tf; then ok "subnet is named AzureBastionSubnet"; else bad "subnet name is wrong"; fi

# the GatewayManager rule exists in the rule set
if grep -Eq 'source[[:space:]]*=[[:space:]]*"GatewayManager"' main.tf; then ok "GatewayManager rule is defined"; else bad "GatewayManager rule missing"; fi

# the VM has no public IP by default: the public IP is only attached under the vm_public_ip switch
if grep -Eq 'public_ip_address_id[[:space:]]*=[[:space:]]*var\.vm_public_ip[[:space:]]*\?' workload.tf; then ok "vm public IP only under the switch"; else bad "vm public IP is not gated"; fi

# the helper is read-only: no create, delete, update or set verbs
if grep -En 'az[[:space:]].*[[:space:]](create|delete|update|set)([[:space:]]|$)' scripts/bastion-check.sh; then bad "bastion-check.sh is not read-only"; else ok "bastion-check.sh is read-only"; fi

# the audit log category is configured
if grep -Eq 'category[[:space:]]*=[[:space:]]*"BastionAuditLogs"' bastion.tf; then ok "BastionAuditLogs diagnostic category"; else bad "missing BastionAuditLogs category"; fi
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
