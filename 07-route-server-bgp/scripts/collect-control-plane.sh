#!/usr/bin/env bash
# Future scoped read-only Azure observations. No VM execution or auto extension install.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network routeserver show -g "$RG" -n routeserver -o json > "$OUT/routeserver.json"
az_read network routeserver peering list -g "$RG" --routeserver routeserver -o json > "$OUT/peerings.json"
for node in nva1 nva2; do
  az_read network routeserver peering show -g "$RG" --routeserver routeserver -n "peer-$node" -o json > "$OUT/$node-peering.json"
  az_read network routeserver peering list-learned-routes -g "$RG" --routeserver routeserver -n "peer-$node" -o json > "$OUT/$node-rs-learned-routes.json"
  az_read network routeserver peering list-advertised-routes -g "$RG" --routeserver routeserver -n "peer-$node" -o json > "$OUT/$node-rs-advertised-routes.json"
done
for role in app remote nva1 nva2; do
  az_read network nic show -g "$RG" -n "$role-nic" -o json > "$OUT/$role-nic.json"
  az_read network nic show-effective-route-table -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-routes.json"
  az_read network nic list-effective-nsg -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-nsg.json"
done
for role in app remote; do
  az_read network route-table show -g "$RG" -n "$role-routes" -o json > "$OUT/$role-route-table.json"
  az_read network vnet subnet show -g "$RG" --vnet-name "$role" -n workload -o json > "$OUT/$role-subnet.json"
done
az_read network route-table show -g "$RG" -n nva-substrate -o json > "$OUT/nva-route-table.json"
for subnet in RouteServerSubnet nva AzureBastionSubnet; do az_read network vnet subnet show -g "$RG" --vnet-name hub -n "$subnet" -o json > "$OUT/$subnet-subnet.json"; done
for vnet in hub app remote; do az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"; done
az_read monitor metrics list-definitions --resource "$RS_ID" -o json > "$OUT/metric-definitions.json"
printf 'Saved scoped metadata. Select current documented per-peer/per-instance metrics separately; Data Processed metric is not applicable.\n'
