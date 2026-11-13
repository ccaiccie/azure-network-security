#!/usr/bin/env bash
# Future approved configuration READS only. Never a runtime path/auth verdict.
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
printf '%s\n' 'PRIVATE: --query is client-side filtering after complete API response receipt, not a secrecy boundary. Metadata/tags/errors/CLI state and declared outputs require private review. VM identity read can involve full VM response before projection. No intentional bootstrap export, listKeys, SAS generation, IMDS, token/Blob request, raw Terraform state/show/plan export, debug or upload. Storage/workspace resources may export keys into Terraform state despite disabled key/local auth. Do not enter secrets in tags. Share only reviewed sanitized copies.' > "$OUT/PRIVATE-HANDLING-REQUIRED.txt"
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
FAILED=0
collect() {
 local name=$1 rc=0; shift
 if az_read "$@" -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr"; then :; else rc=$?; FAILED=$((FAILED+1)); fi
 printf '%s\n' "$rc" > "$OUT/$name.exit"
}
collect account account show --query '{subscription:id,tenant:tenantId,name:name}'
collect firewall resource show --ids "$(read_output firewall_id)" --query '{id:id,properties:{provisioningState:properties.provisioningState,sku:properties.sku,ipConfigurations:properties.ipConfigurations,firewallPolicy:properties.firewallPolicy}}'
collect policy resource show --ids "$(read_output firewall_policy_id)" --query '{id:id,properties:{provisioningState:properties.provisioningState,sku:properties.sku,dnsSettings:properties.dnsSettings,snat:properties.snat,basePolicy:properties.basePolicy,threatIntelMode:properties.threatIntelMode}}'
collect rules resource show --ids "$(read_output firewall_policy_id)/ruleCollectionGroups/blob-rules" --api-version 2025-01-01 --query '{id:id,properties:properties}'
for role in reader seed; do
 collect "$role-nic" network nic show --ids "$(read_map_output nic_ids "$role")"
 collect "$role-effective-routes" network nic show-effective-route-table -g "$RG" -n "$role-nic"
 collect "$role-effective-nsg" network nic list-effective-nsg -g "$RG" -n "$role-nic"
 collect "$role-identity" vm show --ids "$(read_map_output vm_ids "$role")" --query '{id:id,identity:identity}'
 if [[ $(read_map_output role_grants "$role") == True ]]; then
  collect "$role-grant" resource show --ids "$(read_map_output role_assignment_ids "$role")" --api-version 2022-04-01 --query '{id:id,properties:{scope:properties.scope,principalId:properties.principalId,principalType:properties.principalType,roleDefinitionId:properties.roleDefinitionId}}'
 else printf 'No role assignment requested for this identity.\n' > "$OUT/$role-role-NOT-ENABLED.txt"; fi
done
for role in hub client endpoint management; do
 collect "$role-vnet" network vnet show --ids "$(read_map_output vnet_ids "$role")"
 collect "$role-peerings" network vnet peering list -g "$RG" --vnet-name "$role"
done
collect client-route-table network route-table show --ids "$(read_output route_table_id)"
collect endpoint resource show --ids "$(read_output endpoint_id)" --api-version 2024-05-01 --query '{id:id,properties:{provisioningState:properties.provisioningState,subnet:properties.subnet,networkInterfaces:properties.networkInterfaces,ipConfigurations:properties.ipConfigurations,privateLinkServiceConnections:properties.privateLinkServiceConnections,manualPrivateLinkServiceConnections:properties.manualPrivateLinkServiceConnections,customDnsConfigs:properties.customDnsConfigs}}'
collect endpoint-subnet network vnet subnet show --ids "$(read_output endpoint_subnet_id)"
collect endpoint-nsg network nsg show --ids "$(read_output endpoint_nsg_id)"
collect endpoint-zone-group network private-endpoint dns-zone-group list -g "$RG" --endpoint-name blob-pe
collect private-zone network private-dns zone show --ids "$(read_output private_dns_zone_id)"
collect private-zone-links network private-dns link vnet list -g "$RG" --zone-name privatelink.blob.core.windows.net
collect private-zone-records network private-dns record-set a list -g "$RG" --zone-name privatelink.blob.core.windows.net
collect storage storage account show --ids "$(read_output storage_account_id)" --query '{id:id,name:name,kind:kind,sku:sku,enableHttpsTrafficOnly:enableHttpsTrafficOnly,minimumTlsVersion:minimumTlsVersion,publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess,allowBlobPublicAccess:allowBlobPublicAccess,networkRuleSet:networkRuleSet,primaryEndpoints:primaryEndpoints,privateEndpointConnections:privateEndpointConnections}'
collect container resource show --ids "$(read_output container_id)" --api-version 2025-08-01 --query '{id:id,properties:{publicAccess:properties.publicAccess,hasImmutabilityPolicy:properties.hasImmutabilityPolicy,hasLegalHold:properties.hasLegalHold}}'
collect bastion resource show --ids "$(read_output bastion_id)"
printf '%s\n' 'REQUIRED: PE Approved state, exact owned storage target/subresource/address, actual client route E/32→F and direct competitor, Enabled PE policies, exact NSGs, F onward endpoint reachability without recursive route, private zone/record/TTL and ordinary hostname DNS. IP allocation alone is insufficient; customDnsConfigs may be empty with valid zone group. No PE NIC effective-route/security or inbound flow-log support is invented. Correlate client tuple/time/FQDN with AZFWApplicationRule and service ClientRequestId with StorageBlobLogs.403 is not authenticated blob access or private inspection proof; reader200 plus fixed content hash establishes only data access, still needs path evidence. Empty/missing fields remain incomplete.' > "$OUT/runtime-evidence-REQUIRED.txt"
printf 'collection_failures=%s\nroute_verification=NOT_PERFORMED\ninspection_verification=NOT_PERFORMED\nblob_access_verification=NOT_PERFORMED\n' "$FAILED" > "$OUT/summary.txt"
printf 'Saved private results to %s; failures=%s; runtime review required.\n' "$OUT" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 3
