#!/usr/bin/env bash
# Read-only helper for the DDoS lab. Designed, not tested. It only reads settings with az CLI;
# it creates, changes and deletes nothing and it never sends traffic to anything.
# Usage: ./scripts/ddos-check.sh tier|ip|diag|alerts|metrics|queries|all
set -euo pipefail
RG="${RG:-ddos29-rg}"
VNET="${VNET:-ddos29-vnet}"
WEB="${WEB:-ddos29-pip-web}"
SPARE="${SPARE:-ddos29-pip-spare}"
PLAN="${PLAN:-ddos29-plan}"
ALERT="${ALERT:-ddos29-under-attack}"

tier() {
  echo "== VNet link to a DDoS plan (null plan = platform baseline only) =="
  az network vnet show -g "$RG" -n "$VNET" --query "{plan:ddosProtectionPlan.id, enabled:enableDdosProtection}" -o json
  echo "== The plan, if it exists, and the VNets linked to it =="
  az network ddos-protection show -g "$RG" -n "$PLAN" --query "{name:name, vnets:virtualNetworks[].id}" -o json 2>/dev/null || echo "no plan named $PLAN"
}
ip() {
  echo "== Public IPs: mode and attachment (mode alone does not prove coverage) =="
  az network public-ip list -g "$RG" \
    --query "[].{name:name, sku:sku.name, mode:ddosSettings.protectionMode, plan:ddosSettings.ddosProtectionPlan.id, attached:ipConfiguration.id}" -o table
}
diag() {
  echo "== Diagnostic setting on pip-web: DDoS log categories =="
  local id
  id="$(az network public-ip show -g "$RG" -n "$WEB" --query id -o tsv)"
  az monitor diagnostic-settings list --resource "$id" \
    --query "value[].{name:name, logs:logs[].category, workspace:workspaceId}" -o json
}
alerts() {
  echo "== Alert rule scope, signal and state =="
  az monitor metrics alert show -g "$RG" -n "$ALERT" \
    --query "{scopes:scopes, metric:criteria.allOf[0].metricName, enabled:enabled}" -o json
  echo "Scope must be the protected IP ($WEB), not $SPARE and not the VNet."
}
metrics() {
  echo "== Metric definitions that mention DDoS (names: check current docs) =="
  local id
  id="$(az network public-ip show -g "$RG" -n "$WEB" --query id -o tsv)"
  az monitor metrics list-definitions --resource "$id" --query "[?contains(name.value, 'DDoS')].name.value" -o tsv
}
queries() {
  echo "Saved queries: queries/ddos-queries.kql"
  echo "Categories: DDoSProtectionNotifications, DDoSMitigationFlowLogs, DDoSMitigationReports"
}
case "${1:-all}" in
  tier) tier ;;
  ip) ip ;;
  diag) diag ;;
  alerts) alerts ;;
  metrics) metrics ;;
  queries) queries ;;
  all) tier; ip; diag; alerts; metrics; queries ;;
  *) echo "usage: $0 tier|ip|diag|alerts|metrics|queries|all" >&2; exit 2 ;;
esac
