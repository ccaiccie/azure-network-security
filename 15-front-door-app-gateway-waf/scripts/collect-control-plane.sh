#!/usr/bin/env bash
# Configuration/read-only health evidence, NOT route/packet/WAF proof.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
OUT=${1:-"$ROOT/evidence-control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
python3 - "$OUT" <<'DIR'
from pathlib import Path
import sys
p=Path(sys.argv[1])
if p.exists() or p.is_symlink() or any(x.is_symlink() for x in p.parents):raise SystemExit('Evidence directory must be new and have no symlink ancestor')
p.mkdir(mode=0o700,parents=True)
DIR
printf '%s\n' "$TF_OUTPUTS" > "$OUT/declared-outputs.json"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/started-utc.txt"
cat > "$OUT/PRIVATE-HANDLING-REQUIRED.txt" <<'NOTICE'
Private evidence. CLI --query filters client-side retained stdout, not complete API response receipt. Metadata, declared values and stderr may be sensitive; review before sharing. No Key Vault secret value, app settings, publishing credentials, TLS key, state or plan is requested. Missing/empty data is inconclusive. No hidden gateway/App Service NIC route query exists here.
NOTICE
failures=0
capture() {
 local name=$1;shift
 if az_read "$@" --only-show-errors -o json > "$OUT/$name.json" 2> "$OUT/$name.stderr";then rc=0;else rc=$?;failures=$((failures+1));fi
 printf '%s\n' "$rc" > "$OUT/$name.exit"
}
capture gateway network application-gateway show --ids "$(read_output gateway_id)" --query '{id:id,name:name,provisioningState:provisioningState,sku:sku,firewallPolicy:firewallPolicy,identity:identity,httpListeners:httpListeners,backendAddressPools:backendAddressPools,backendHttpSettingsCollection:backendHttpSettingsCollection,probes:probes,requestRoutingRules:requestRoutingRules,sslPolicy:sslPolicy,sslCertificates:sslCertificates[].{name:name,keyVaultSecretId:keyVaultSecretId}}'
capture backend-health network application-gateway show-backend-health --ids "$(read_output gateway_id)" --query '{backendAddressPools:backendAddressPools}'
capture subnet network vnet subnet show --ids "$(read_output gateway_subnet_id)" --query '{id:id,addressPrefix:addressPrefix,addressPrefixes:addressPrefixes,networkSecurityGroup:networkSecurityGroup,routeTable:routeTable}'
capture gateway-nsg network nsg show --ids "$(read_output gateway_nsg_id)" --query '{id:id,securityRules:securityRules,defaultSecurityRules:defaultSecurityRules}'
capture gateway-waf network application-gateway waf-policy show --ids "$(read_output gateway_waf_policy_id)" --query '{id:id,policySettings:policySettings,customRules:customRules,managedRules:managedRules}'
capture edge-waf resource show --ids "$(read_output edge_waf_policy_id)" --query '{id:id,policySettings:properties.policySettings,customRules:properties.customRules,managedRules:properties.managedRules}'
# Generic resource reads avoid hidden extension installation; scope IDs are guarded.
capture profile resource show --ids "$(read_output frontdoor_profile_id)" --query '{id:id,sku:sku,frontDoorId:properties.frontDoorId,provisioningState:properties.provisioningState,originResponseTimeoutSeconds:properties.originResponseTimeoutSeconds}'
capture endpoint resource show --ids "$(read_output edge_endpoint_id)" --query '{id:id,hostName:properties.hostName,enabledState:properties.enabledState,provisioningState:properties.provisioningState}'
capture edge-route resource show --ids "$(read_output edge_route_id)" --query '{id:id,enabledState:properties.enabledState,originGroup:properties.originGroup,patternsToMatch:properties.patternsToMatch,supportedProtocols:properties.supportedProtocols,forwardingProtocol:properties.forwardingProtocol,httpsRedirect:properties.httpsRedirect,cacheConfiguration:properties.cacheConfiguration,ruleSets:properties.ruleSets}'
capture origin-group resource show --ids "$(read_output origin_group_id)" --query '{id:id,healthProbeSettings:properties.healthProbeSettings,loadBalancingSettings:properties.loadBalancingSettings,sessionAffinityState:properties.sessionAffinityState}'
capture origin resource show --ids "$(read_output origin_id)" --query '{id:id,enabledState:properties.enabledState,hostName:properties.hostName,originHostHeader:properties.originHostHeader,httpsPort:properties.httpsPort,enforceCertificateNameCheck:properties.enforceCertificateNameCheck}'
capture edge-security resource show --ids "$(read_output security_policy_id)" --query '{id:id,parameters:properties.parameters}'
capture backend webapp show --ids "$(read_output backend_id)" --query '{id:id,name:name,state:state,defaultHostName:defaultHostName,httpsOnly:httpsOnly,publicNetworkAccess:publicNetworkAccess,enabled:enabled}'
capture backend-restrictions webapp config access-restriction show --resource-group "$RG" --name "$BACKEND" --query '{ipSecurityRestrictions:ipSecurityRestrictions,ipSecurityRestrictionsDefaultAction:ipSecurityRestrictionsDefaultAction,scmIpSecurityRestrictions:scmIpSecurityRestrictions,scmIpSecurityRestrictionsDefaultAction:scmIpSecurityRestrictionsDefaultAction,scmIpSecurityRestrictionsUseMain:scmIpSecurityRestrictionsUseMain}'
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/completed-utc.txt"
printf 'failed_reads=%s\nconfiguration_health_only=true\nruntime_path_waf_verification=NOT_PERFORMED\n' "$failures" > "$OUT/summary.txt"
printf 'Saved private evidence: %s; failed reads: %s. Inspect actual policy/health/data; no automatic pass.\n' "$OUT" "$failures"
[[ $failures == 0 ]]
