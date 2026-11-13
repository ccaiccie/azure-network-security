#!/usr/bin/env bash
# Scoped read-only metadata. --query filters normal stdout client-side, not the API response.
# VPN connection-list receipt requires explicit per-invocation acknowledgement below.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
COLLECT_VPN_CONNECTIONS=false
if [[ ${1:-} == --acknowledge-full-vpn-response ]]; then COLLECT_VPN_CONNECTIONS=true; shift; fi
[[ $# -le 1 && ${1:-} != --* ]] || { printf 'Usage: collect-control-plane.sh [--acknowledge-full-vpn-response] [NEW_OUT]\n' >&2; exit 2; }
require_extensions virtual-wan
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
cat > "$OUT/PRIVATE-HANDLING-REQUIRED.txt" <<'NOTICE'
PRIVATE EVIDENCE: Azure CLI --query filters returned JSON client-side, not server-side. The 2025-05-01 Swagger documents link sharedKey omitted from Get/List responses and legacy connection sharedKey deprecated/unused; no PSK receipt is asserted. Other response metadata, resource tags, errors and diagnostic logs can still contain sensitive text. Do not enable debug, verbose or shell tracing. Declared Terraform outputs, including operator-supplied provider_profile free text, are copied without redaction. Enter no sensitive data in profile fields. Keep evidence and CLI logs private; review/redact an approved copy before sharing. No general automatic redaction or guarantee of sensitive-data absence is provided.
NOTICE
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
  local name=$1 rc=0; shift
  if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
  printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
for pair in 'vwan:vwan_id' 'hub:hub_id' 'management:management_vnet_id'; do collect "${pair%%:*}" resource show --ids "$(read_output "${pair#*:}")"; done
collect gateway-projected resource show --ids "$GATEWAY_ID" --api-version 2025-05-01 --query '{id:id,type:type,location:location,provisioning_state:properties.provisioningState,hub_id:properties.virtualHub.id,scale_unit:properties.vpnGatewayScaleUnit}'
if [[ "$(read_optional_output spp_id)" != None ]]; then
  collect spp-projected resource show --ids "$(read_optional_output spp_id)" --api-version 2025-07-01 --query '{id:id,type:type,location:location,provider:properties.securityProviderName,hub_id:properties.virtualHub.id,provisioning_state:properties.provisioningState,connection_status:properties.connectionStatus}'
else printf 'SPP association disabled; external onboarding/path cannot be assumed.\n' > "$OUT/spp-NOT-ENABLED.txt"; fi
# The response arrives before stdout filtering. Opt-in is a conservative local choice,
# not a claim that documented Get/List responses contain shared keys.
if [[ "$COLLECT_VPN_CONNECTIONS" == true ]]; then
printf 'Explicit per-invocation acknowledgement: receive the full returned VPN collection before client-side filtering. Keep response metadata/diagnostics private; review before sharing.\n' > "$OUT/vpn-response-read-ACKNOWLEDGED.txt"
collect vpn-connections-projected rest --method get --url "https://management.azure.com${GATEWAY_ID}/vpnConnections?api-version=2025-05-01" --query '{next_link:nextLink,connections:value[].{id:id,name:name,provisioning_state:properties.provisioningState,connection_status:properties.connectionStatus,site_id:properties.remoteVpnSite.id,ingress_bytes:properties.ingressBytesTransferred,egress_bytes:properties.egressBytesTransferred,links:properties.vpnLinkConnections[].{id:id,name:name,provisioning_state:properties.provisioningState,connection_status:properties.connectionStatus,ingress_bytes:properties.ingressBytesTransferred,egress_bytes:properties.egressBytesTransferred,site_link_id:properties.vpnSiteLink.id,protocol:properties.vpnConnectionProtocolType}}}'
if [[ "$(cat "$OUT/vpn-connections-projected.exit")" == 0 ]]; then
  if python3 - "$OUT/vpn-connections-projected.json" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]))
if not isinstance(v,dict) or not isinstance(v.get('connections'),list):raise SystemExit(2)
if v.get('next_link'):raise SystemExit(3)
PY
  then :; else FAILED=$((FAILED+1)); printf 'INCOMPLETE/invalid connection projection or pagination. Preserve it; manually complete a scoped projected read before tunnel conclusions.\n' > "$OUT/vpn-projection-INCOMPLETE.txt"; fi
fi
else
printf 'SKIPPED by default: VPN connection collection not requested. Obtain separately authorized, reviewed/sanitized Azure-side connection/link inventory and state from the responsible operator, plus ZIA-side evidence. Missing tunnel evidence remains NOT VERIFIED. The optional --acknowledge-full-vpn-response flag acknowledges full response receipt before client-side filtering; it is not proof of authorization or redaction.\n' > "$OUT/vpn-connections-SKIPPED.txt"
fi
collect app-connection network vhub connection show -g "$RG" --vhub-name "$HUB" -n connect-app
collect hub-connections network vhub connection list -g "$RG" --vhub-name "$HUB"
collect hub-route-tables network vhub route-table list -g "$RG" --vhub-name "$HUB"
collect default-effective-routes network vhub get-effective-routes -g "$RG" -n "$HUB" --resource-type RouteTable --resource-id "$(read_output hub_default_route_table_id)"
for role in app origin1 origin2; do
  collect "$role-nic" network nic show -g "$RG" -n "$role-nic"
  collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
  collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
done
for network in app origin; do
  collect "$network-workload-subnet" network vnet subnet show -g "$RG" --vnet-name "$network" -n workload
  collect "$network-peerings" network vnet peering list -g "$RG" --vnet-name "$network"
done
for network in management origin; do collect "$network-bastion-subnet" network vnet subnet show -g "$RG" --vnet-name "$network" -n AzureBastionSubnet; done
collect management-peerings network vnet peering list -g "$RG" --vnet-name management
for role in origin1 origin2; do collect "$role-public-ip" resource show --ids "$(read_map_output origin_public_ip_ids "$role")"; done
printf '%s\n' 'REQUIRED: actual Azure AND ZIA tunnel inventory/state, observed G/Z outer endpoints/transport, selected source default and hub ownership, activated location/client policy revision/category/action, original and proxy-side transaction evidence, reviewed full E pool and origin journals. SPP Succeeded/Connected, byte counts, HTTP200, Block HTML or timeout alone prove neither policy nor end-to-end path. No universal fail-open/fail-closed claim.' > "$OUT/provider-runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nvpn_connection_read_opted_in=%s\nroute_verification=NOT_PERFORMED\ntunnel_verification=NOT_PERFORMED\nprovider_policy_verification=NOT_PERFORMED\n' "$FAILED" "$COLLECT_VPN_CONNECTIONS" > "$OUT/summary.txt"
printf 'Saved private evidence to %s; failed reads/incomplete pages=%s. Review/redact before sharing; manual provider correlation remains required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
