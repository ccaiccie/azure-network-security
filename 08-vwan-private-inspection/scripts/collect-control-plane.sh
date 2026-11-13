#!/usr/bin/env bash
# Read-only metadata collection, NOT route/path verification. No guest execution.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
[[ $# -le 1 ]] || { printf 'Usage: collect-control-plane.sh [NEW_OUT]\n' >&2; exit 2; }
require_extensions virtual-wan azure-firewall
if [[ -n ${FIREWALL_ROUTE_RESOURCE_TYPE:-} ]]; then
  [[ "$FIREWALL_ROUTE_RESOURCE_TYPE" =~ ^[A-Za-z][A-Za-z0-9]{0,63}$ ]] || { printf 'Invalid optional candidate type.\n' >&2; exit 2; }
fi
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
  local name=$1 rc=0; shift
  if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
  printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
for pair in 'vwan:vwan_id' 'hub:hub_id' 'firewall:firewall_id' 'policy:firewall_policy_id' 'intent:routing_intent_id'; do
  collect "${pair%%:*}" resource show --ids "$(read_output "${pair#*:}")"
done
collect rules network firewall policy rule-collection-group show -g "$RG" --policy-name private-policy -n private-rules
for role in app backend; do
  collect "$role-connection" network vhub connection show -g "$RG" --vhub-name "$HUB" -n "connect-$role"
  collect "$role-nic" network nic show -g "$RG" -n "$role-nic"
  collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
  collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
  collect "$role-route-table" network route-table show -g "$RG" -n "$role-outbound-safety"
  collect "$role-workload-subnet" network vnet subnet show -g "$RG" --vnet-name "$role" -n workload
  collect "$role-bastion-subnet" network vnet subnet show -g "$RG" --vnet-name "$role" -n AzureBastionSubnet
  collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
collect hub-route-tables network vhub route-table list -g "$RG" --vhub-name "$HUB"
collect default-effective-routes network vhub get-effective-routes -g "$RG" -n "$HUB" --resource-type RouteTable --resource-id "$(read_output hub_default_route_table_id)"
printf '%s\n' 'REQUIRED: manually save actual secured-hub Effective Routes > Azure Firewall view for hub-firewall, showing onward routes to BOTH app and backend connections. Record selected resource, UTC, prefix/type/next hop/origin and subscription. Default route table/NIC output alone cannot replace this view. Empty or unsupported API output is NOT verification.' > "$OUT/firewall-onward-routes-REQUIRED.txt"
if [[ -n ${FIREWALL_ROUTE_RESOURCE_TYPE:-} ]]; then
  printf 'UNVERIFIED optional CLI/API candidate resource-type=%s; exact firewall token is not established by primary CLI schema. Preserve failure. No empty success counts as proof.\n' "$FIREWALL_ROUTE_RESOURCE_TYPE" > "$OUT/firewall-candidate-NOT-VERIFIED.txt"
  collect firewall-effective-routes-candidate network vhub get-effective-routes -g "$RG" -n "$HUB" --resource-type "$FIREWALL_ROUTE_RESOURCE_TYPE" --resource-id "$FW_ID"
fi
collect firewall-diagnostics monitor diagnostic-settings list --resource "$FW_ID"
collect firewall-metric-definitions monitor metrics list-definitions --resource "$FW_ID"
printf 'collection_failures=%s\nroute_verification=NOT_PERFORMED\nfirewall_onward_portal_evidence=REQUIRED\n' "$FAILED" > "$OUT/summary.txt"
printf 'Saved metadata to %s; failed reads=%s. Manual route/policy/fixture/log correlation remains required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
