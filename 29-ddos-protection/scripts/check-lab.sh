#!/usr/bin/env bash
# Static check of the lab files. Designed, not tested against Azure: it only reads local files.
# Whitespace-tolerant on purpose, so `terraform fmt` realigning '=' never breaks it.
# Usage: ./scripts/check-lab.sh   (run from the terraform folder)
set -u
cd "$(dirname "$0")/.."
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# every gate and the acknowledgement default to false
for v in deploy_workload deploy_monitoring deploy_ddos_network_protection accept_ddos_plan_cost deploy_ip_protection; do
  if awk -v v="$v" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" v "\"" {inblk=1}
    inblk && $0 ~ /^[[:space:]]*default[[:space:]]*=[[:space:]]*false[[:space:]]*$/ {found=1}
    inblk && $0 ~ /^}/ {inblk=0}
    END {exit found ? 0 : 1}' variables.tf; then ok "gate $v defaults to false"; else bad "gate $v does not default to false"; fi
done

# the plan needs both switches
if grep -Eq 'plan_on[[:space:]]*=[[:space:]]*var\.deploy_ddos_network_protection[[:space:]]*&&[[:space:]]*var\.accept_ddos_plan_cost' main.tf; then ok "plan needs both switches"; else bad "plan_on does not need both switches"; fi
if grep -Eq 'count[[:space:]]*=[[:space:]]*local\.plan_on' ddos.tf; then ok "plan resource is counted by plan_on"; else bad "plan resource is not gated"; fi

# the cost warning is prominent
if grep -Eiq 'COST WARNING' variables.tf && grep -Eiq 'COSTLY' variables.tf; then ok "cost warnings present"; else bad "cost warnings missing"; fi

# defensive only: no traffic generation in any script or Terraform file
if grep -RIEn '(/dev/(tcp|udp)/|while[[:space:]]+true|seq[[:space:]]+[0-9]+[[:space:]]+[0-9]{4,})' --include='*.sh' --include='*.tf' --include='*.tftpl' . | grep -v 'check-lab.sh' ; then bad "possible traffic generator"; else ok "no traffic generator"; fi

# read-only helper: no create, delete or update verbs
if grep -En 'az[[:space:]].*[[:space:]](create|delete|update|set)([[:space:]]|$)' scripts/ddos-check.sh; then bad "ddos-check.sh is not read-only"; else ok "ddos-check.sh is read-only"; fi

# diagnostics on the public IP and all three categories
for c in DDoSProtectionNotifications DDoSMitigationFlowLogs DDoSMitigationReports; do
  if grep -Eq "category[[:space:]]*=[[:space:]]*\"$c\"" monitoring.tf; then ok "diagnostic category $c"; else bad "missing diagnostic category $c"; fi
done
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
