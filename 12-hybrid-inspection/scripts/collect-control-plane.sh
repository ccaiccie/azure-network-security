#!/usr/bin/env bash
# READS only. Default skips potentially secret-bearing connection GET responses.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ACK=false
if [[ ${1:-} == --acknowledge-sensitive-connection-response ]]; then ACK=true; shift; fi
[[ $# -le 1 && ${1:-} != --* ]] || { printf 'Usage: collect-control-plane.sh [--acknowledge-sensitive-connection-response] [NEW_OUT]\n' >&2; exit 2; }
load_context
command -v az >/dev/null
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
printf '%s\n' 'PRIVATE: --query is client-side filtering after the complete API response arrives. It is not server-side minimization/redaction. Metadata, tags, errors, CLI diagnostics and declared Terraform outputs are not automatically redacted. Never put secrets in tags. No shared-key endpoint, state/show/plan export, VM bootstrap read, debug or automatic upload. Review an approved sanitized copy before sharing; Terraform state itself contains PSK and may contain workspace shared keys.' > "$OUT/PRIVATE-HANDLING-REQUIRED.txt"
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
 local name=$1 rc=0; shift
 if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
 printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
collect firewall resource show --ids "$(read_output firewall_id)" --query '{id:id,type:type,location:location,properties:{provisioningState:properties.provisioningState,sku:properties.sku,ipConfigurations:properties.ipConfigurations,firewallPolicy:properties.firewallPolicy}}'
collect policy resource show --ids "$(read_output firewall_policy_id)" --query '{id:id,properties:{provisioningState:properties.provisioningState,sku:properties.sku,basePolicy:properties.basePolicy,snat:properties.snat,threatIntelMode:properties.threatIntelMode}}'
collect rules resource show --ids "$(read_output firewall_policy_id)/ruleCollectionGroups/hybrid-rules" --api-version 2025-01-01 --query '{id:id,properties:properties}'
for role in branch spoke; do
 collect "$role-nic" network nic show --ids "$(read_map_output nic_ids "$role")"
 collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
 collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
done
for role in hub branch spoke management; do
 collect "$role-vnet" network vnet show --ids "$(read_map_output vnet_ids "$role")"
 collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
for role in gateway branch spoke; do collect "$role-routes" network route-table show --ids "$(read_map_output route_table_ids "$role")"; done
for role in hub branch; do
 collect "$role-gateway" network vnet-gateway show --ids "$(read_map_output gateway_ids "$role")" --query '{id:id,name:name,location:location,provisioningState:provisioningState,gatewayType:gatewayType,vpnType:vpnType,sku:sku,activeActive:activeActive,enableBgp:enableBgp,ipConfigurations:ipConfigurations,natRules:natRules}'
 collect "$role-gateway-public-ip" network public-ip show --ids "$(read_map_output gateway_public_ip_ids "$role")"
 collect "$role-gateway-metric-definitions" monitor metrics list-definitions --resource "$(read_map_output gateway_ids "$role")"
done
for role in branch azure; do collect "$role-bastion" resource show --ids "$(read_map_output bastion_ids "$role")"; done
CONNECTION_READS=false
if [[ $(read_output connections_enabled) != True ]]; then
 printf 'Both owned Vnet2Vnet connections are disabled. No connection reads attempted.\n' > "$OUT/connections-NOT-ENABLED.txt"
elif [[ "$ACK" == true ]]; then
 CONNECTION_READS=true
 printf '%s\n' 'Explicit invocation acknowledgment: complete connection GET responses may contain sensitive fields. The reviewed generic schema lists sharedKey; omission is not guaranteed here. Client-side projection only limits retained stdout, not received content, error/debug logs or caches. No secret value is deliberately projected. Keep all output/CLI state private.' > "$OUT/connection-read-ACKNOWLEDGED.txt"
 for name in hub-to-branch branch-to-hub; do
  collect "$name-connection" network vpn-connection show --ids "$(read_map_output connection_ids "$name")" --query '{id:id,name:name,provisioningState:provisioningState,connectionType:connectionType,connectionStatus:connectionStatus,enableBgp:enableBgp,ingressBytesTransferred:ingressBytesTransferred,egressBytesTransferred:egressBytesTransferred,tunnelConnectionStatus:tunnelConnectionStatus,virtualNetworkGateway1:virtualNetworkGateway1.id,virtualNetworkGateway2:virtualNetworkGateway2.id}'
 done
else
 printf '%s\n' 'SKIPPED: connection GETs may return sensitive fields before client-side --query. Obtain sanitized status/tunnel/peer identity evidence through the approved operator workflow; do not open shared-key panels or export full connection/state. Optional helper flag acknowledges response handling, not permission to share secrets.' > "$OUT/connections-SKIPPED.txt"
fi
printf '%s\n' 'REQUIRED: both intended connection statuses and remote identities; actual A NIC spoke-prefix gateway route; GatewaySubnet exact route association with propagation enabled; firewall onward branch path; B UDR/propagation-disabled path; no NAT, broad default or bypass; policy and exact AZFWNetworkRule tuple/rule/action rows; local healthy listener/readiness and backend original source. No supported managed gateway/firewall hidden-NIC effective-route command is invented. Missing/null/empty fields and Connected alone are inconclusive. Metric definitions are not measured tunnel or packet evidence.' > "$OUT/runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nconnection_response_reads=%s\nroute_verification=NOT_PERFORMED\ninspection_verification=NOT_PERFORMED\n' "$FAILED" "$CONNECTION_READS" > "$OUT/summary.txt"
printf 'Saved private read results to %s; failures=%s; runtime review still required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
