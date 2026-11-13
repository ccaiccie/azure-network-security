#!/usr/bin/env bash
# Read-only evidence collector for the ExpressRoute multi-region lab.
# DESIGNED, NOT TESTED: this script was never run. It changes nothing in Azure.
# Usage: RG=... CIRCUIT_A=... CIRCUIT_B=... GW_A=... GW_B=... ./scripts/er-evidence.sh [new-output-dir]
set -euo pipefail
: "${RG:?set the resource group}" "${CIRCUIT_A:?}" "${CIRCUIT_B:?}" "${GW_A:?}" "${GW_B:?}"
OUT=${1:-"./evidence-$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -- "$OUT" || { echo "Use a NEW output directory" >&2; exit 2; }

collect() {  # name, then the az command
  local name=$1; shift
  if "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.err"; then echo 0 > "$OUT/$name.exit"; else echo $? > "$OUT/$name.exit"; fi
}

for c in "$CIRCUIT_A" "$CIRCUIT_B"; do
  collect "$c-state" az network express-route show -g "$RG" -n "$c"
  for path in primary secondary; do
    collect "$c-$path-arp" az network express-route list-arp-tables -g "$RG" -n "$c" --peering-name AzurePrivatePeering --path "$path"
    collect "$c-$path-routes" az network express-route list-route-tables -g "$RG" -n "$c" --peering-name AzurePrivatePeering --path "$path"
  done
done
for g in "$GW_A" "$GW_B"; do
  collect "$g-learned" az network vnet-gateway list-learned-routes -g "$RG" -n "$g"
done
echo "Evidence written to $OUT (check each .exit file)"
