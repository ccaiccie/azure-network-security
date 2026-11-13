#!/usr/bin/env bash
# Future scoped read-only Azure metadata, no VM execution or guest mutation.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Choose a NEW nonexistent evidence path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'status=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$status" >> "$OUT/timing.txt"' EXIT
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network lb show -g "$RG" -n nva-ilb -o json > "$OUT/lb.json"
az_read network lb frontend-ip list -g "$RG" --lb-name nva-ilb -o json > "$OUT/frontend.json"
az_read network lb address-pool list -g "$RG" --lb-name nva-ilb -o json > "$OUT/backend-pool.json"
az_read network lb rule list -g "$RG" --lb-name nva-ilb -o json > "$OUT/rules.json"
az_read network lb probe list -g "$RG" --lb-name nva-ilb -o json > "$OUT/probes.json"
for role in app backend nva1 nva2; do
  az_read network nic show -g "$RG" -n "$role-nic" -o json > "$OUT/$role-nic-forwarding.json"
  az_read network nic show-effective-route-table -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-routes.json"
  az_read network nic list-effective-nsg -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-nsg.json"
done
for role in app backend; do
  az_read network vnet subnet show -g "$RG" --vnet-name "$role" -n workload -o json > "$OUT/$role-subnet.json"
  az_read network route-table show -g "$RG" -n "$role-inspect" -o json > "$OUT/$role-route-table.json"
done
az_read network vnet subnet show -g "$RG" --vnet-name hub -n nva -o json > "$OUT/nva-subnet.json"
az_read network route-table show -g "$RG" -n nva-block-internet -o json > "$OUT/nva-route-table.json"
for vnet in hub app backend; do az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"; done
az_read monitor metrics list-definitions --resource "$LB_ID" -o json > "$OUT/metric-definitions.json"
# Last-hour aggregate data is supporting evidence, not per-flow selection proof.
az_read monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M --aggregation Average --filter "BackendIPAddress eq '*'" --offset 1h -o json > "$OUT/backend-health-metric.json"
az_read monitor metrics list --resource "$LB_ID" --metric VipAvailability --interval PT1M --aggregation Average --offset 1h -o json > "$OUT/frontend-datapath-metric.json"
printf 'Saved control-plane/aggregate metrics to %s. No actual flow owner or guest readiness inferred.\n' "$OUT"
