#!/usr/bin/env bash
# Approved read-only Azure configuration collection. Never a runtime verdict.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -le 1 && ${1:-} != --* ]] || { printf 'Usage: collect-control-plane.sh [NEW_OUT]\n' >&2; exit 2; }
load_context
command -v az >/dev/null
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
printf '%s\n' 'PRIVATE: --query filters client-side after complete response receipt; it is not a secrecy boundary. Tags, metadata, declared outputs, errors and diagnostics are not universally redacted. Enter no sensitive data into tags. No state/show/plan export, bootstrap read, debug, key endpoint or automatic upload. Review a sanitized copy before sharing; Terraform workspace resource may export shared keys into state despite disabled local auth.' > "$OUT/PRIVATE-HANDLING-REQUIRED.txt"
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
 local name=$1 rc=0; shift
 if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
 printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
collect firewall resource show --ids "$(read_output firewall_id)" --query '{id:id,type:type,location:location,properties:{provisioningState:properties.provisioningState,sku:properties.sku,ipConfigurations:properties.ipConfigurations,managementIpConfiguration:properties.managementIpConfiguration,firewallPolicy:properties.firewallPolicy}}'
collect policy resource show --ids "$(read_output firewall_policy_id)" --query '{id:id,properties:{provisioningState:properties.provisioningState,sku:properties.sku,basePolicy:properties.basePolicy,snat:properties.snat,threatIntelMode:properties.threatIntelMode}}'
collect rules resource show --ids "$(read_output firewall_policy_id)/ruleCollectionGroups/forced-rules" --api-version 2025-01-01 --query '{id:id,properties:properties}'
for role in app perimeter origin; do
 collect "$role-nic" network nic show --ids "$(read_map_output nic_ids "$role")"
 collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
 collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
done
for role in hub app perimeter origin management; do
 collect "$role-vnet" network vnet show --ids "$(read_map_output vnet_ids "$role")"
 collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
for role in app firewall perimeter; do collect "$role-routes" network route-table show --ids "$(read_map_output route_table_ids "$role")"; done
for role in perimeter origin firewall_management bastion; do collect "$role-public-ip" network public-ip show --ids "$(read_map_output public_ip_ids "$role")"; done
collect bastion resource show --ids "$(read_output bastion_id)"
collect firewall-metric-definitions monitor metrics list-definitions --resource "$(read_output firewall_id)"
printf '%s\n' 'REQUIRED: A actual NIC default to F; FirewallSubnet table default to E; perimeter NIC return10.20/16 to F, hub route to S and Internet default; separate management peer paths; no customer table on FirewallManagementSubnet. Managed Firewall has no invented hidden-NIC effective route command. Correlate AZFWNetworkRule action/rule with client tuple, observed A/S at perimeter, guest conntrack E and origin P socket. Empty/missing reads, provisioning status, tables and timeouts are not runtime inspection proof.' > "$OUT/runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nroute_verification=NOT_PERFORMED\ninspection_verification=NOT_PERFORMED\n' "$FAILED" > "$OUT/summary.txt"
printf 'Saved private results to %s; failures=%s; runtime review required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
