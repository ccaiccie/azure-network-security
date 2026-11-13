#!/usr/bin/env bash
# Read-only CLI; full returned metadata/errors may be sensitive. No raw VM bootstrap reads.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
[[ $# -le 1 ]] || { printf 'Usage: collect-control-plane.sh [NEW_OUT]\n' >&2; exit 2; }
command -v az >/dev/null
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
printf '%s\n' 'PRIVATE: --query is client-side output filtering, not server-side minimization. Declared outputs, tags, errors and CLI diagnostics are not automatically redacted. Enter no secrets in tags/metadata. Keep evidence private; review/redact an approved copy before sharing. No debug/verbose/shell tracing or automatic upload.' > "$OUT/PRIVATE-HANDLING-REQUIRED.txt"
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
 local name=$1 rc=0; shift
 if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
 printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
for pair in inspection:inspection-gwlb consumer:public-lb; do
 collect "${pair%%:*}-lb" network lb show -g "$RG" -n "${pair#*:}"
done
collect public-ip network public-ip show --ids "$(read_output consumer_public_ip_id)"
for key in gwlb_id consumer_lb_id; do collect "$key-metric-definitions" monitor metrics list-definitions --resource "$(read_output "$key")"; done
for role in nva1 nva2 app; do
 collect "$role-nic" network nic show --ids "$(read_map_output nic_ids "$role")"
 collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
 collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
done
for role in provider consumer management; do
 collect "$role-vnet" network vnet show --ids "$(read_map_output vnet_ids "$role")"
 collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
collect bastion resource show --ids "$(read_output bastion_id)"
printf '%s\n' 'REQUIRED: actual consumer frontend chain ID, no alternate egress/NIC path, both independent probe histories, per-instance metrics, NSG and routes, bridge/link/MTU/nft policy snapshots and counters, bounded outer+two-inner captures on BOTH NVAs, original client NAT boundary, backend socket/journal, same-instance return and observed translation fields. A healthy probe or HTTP200 alone is not inspection proof. Capture and metadata remain private.' > "$OUT/runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nchain_datapath_verification=NOT_PERFORMED\npolicy_verification=NOT_PERFORMED\n' "$FAILED" > "$OUT/summary.txt"
printf 'Saved private read results to %s; failures=%s. Manual runtime evidence remains required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
