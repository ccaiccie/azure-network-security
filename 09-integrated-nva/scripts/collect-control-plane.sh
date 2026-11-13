#!/usr/bin/env bash
# Read-only Azure commands. --query filters normal stdout client-side, not the API response.
# Treat diagnostics and declared Terraform outputs as private and potentially sensitive.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
[[ $# -le 1 ]] || { printf 'Usage: collect-control-plane.sh [NEW_OUT]\n' >&2; exit 2; }
require_extensions virtual-wan
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
mkdir -- "$OUT" || { printf 'Use a NEW nonexistent output path.\n' >&2; exit 2; }
printf 'started_utc=%s\n' "$(date -u +%FT%TZ)" > "$OUT/timing.txt"
trap 'rc=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$rc" >> "$OUT/timing.txt"' EXIT
cat > "$OUT/PRIVATE-HANDLING-REQUIRED.txt" <<'NOTICE'
PRIVATE EVIDENCE: Azure CLI --query is client-side output filtering. The CLI can receive a full response containing secret-bearing fields before normal stdout projection. Error/diagnostic logs can contain sensitive values; do not enable debug, verbose or shell tracing. No automatic diagnostic redaction is performed. Declared Terraform outputs, including operator-supplied vendor_profile free text, are copied without redaction. Enter no secrets in profile fields. Keep this entire directory and CLI logs private; inspect and redact an approved copy before sharing. This is not proof that raw sensitive data was never received or logged.
NOTICE
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
  local name=$1 rc=0; shift
  if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
  printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
for pair in 'vwan:vwan_id' 'hub:hub_id' 'origin-public-ip:origin_public_ip_id'; do collect "${pair%%:*}" resource show --ids "$(read_output "${pair#*:}")"; done
if [[ "$(read_optional_output routing_intent_id)" != None ]]; then collect intent resource show --ids "$(read_optional_output routing_intent_id)"; fi
collect app-connection network vhub connection show -g "$RG" --vhub-name "$HUB" -n connect-app
for role in app origin; do
  collect "$role-nic" network nic show -g "$RG" -n "$role-nic"
  collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
  collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
  collect "$role-workload-subnet" network vnet subnet show -g "$RG" --vnet-name "$role" -n workload
  MGMT_VNET=$role; [[ "$role" != app ]] || MGMT_VNET=management
  collect "$role-bastion-subnet" network vnet subnet show -g "$RG" --vnet-name "$MGMT_VNET" -n AzureBastionSubnet
  collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
collect management-vnet resource show --ids "$(read_output management_vnet_id)"
collect management-peerings network vnet peering list -g "$RG" --vnet-name management
collect hub-connections network vhub connection list -g "$RG" --vhub-name "$HUB"
collect hub-route-tables network vhub route-table list -g "$RG" --vhub-name "$HUB"
collect default-effective-routes network vhub get-effective-routes -g "$RG" -n "$HUB" --resource-type RouteTable --resource-id "$(read_output hub_default_route_table_id)"
if [[ "$(read_optional_output nva_resource_id)" != None ]]; then
  NVA_ID=$(read_optional_output nva_resource_id)
  APP_ID=$(printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["vendor_profile"]["value"]["managed_application_id"])')
  collect nva-projected resource show --ids "$NVA_ID" --api-version 2025-05-01 --query '{id:id,type:type,location:location,provisioning_state:properties.provisioningState,hub_id:properties.virtualHub.id,vendor:properties.nvaSku.vendor,marketplace_version:properties.nvaSku.marketPlaceVersion,scale_unit:properties.nvaSku.bundledScaleUnit}'
  collect managed-app-projected resource show --ids "$APP_ID" --query '{id:id,type:type,provisioning_state:properties.provisioningState,managed_resource_group_id:properties.managedResourceGroupId,publisher:plan.publisher,product:plan.product,plan_name:plan.name}'
  if [[ "$(cat "$OUT/nva-projected.exit")" == 0 && "$(cat "$OUT/managed-app-projected.exit")" == 0 ]]; then
    rc=0
    python3 "$ROOT/scripts/validate-vendor-identity.py" "$OUT/terraform-outputs.json" "$OUT/nva-projected.json" "$OUT/managed-app-projected.json" > "$OUT/vendor-identity-comparison.json" 2> "$OUT/vendor-identity-comparison.stderr" || rc=$?
    printf '%s\n' "$rc" > "$OUT/vendor-identity-comparison.exit"
    if [[ "$rc" -ne 0 ]]; then FAILED=$((FAILED+1)); fi
  fi
else
  printf 'BLOCKED: external vendor profile/NVA has not been selected and recorded.\n' > "$OUT/vendor-profile-BLOCKED.txt"
fi
printf '%s\n' 'REQUIRED MANUAL: supported vendor compatibility/license/health, installed revision and named exact rule action, all E pool addresses, direct-egress and reverse routes, original/intermediate/final translated tuple fields, session ownership and bounded UTC log export. No generic Azure Firewall KQL or fabricated vendor log schema is supplied.' > "$OUT/vendor-runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nroute_verification=NOT_PERFORMED\nvendor_policy_verification=NOT_PERFORMED\n' "$FAILED" > "$OUT/summary.txt"
printf 'Saved private evidence to %s; failed reads/comparisons=%s. Review/redact before sharing; vendor/runtime evidence still required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
