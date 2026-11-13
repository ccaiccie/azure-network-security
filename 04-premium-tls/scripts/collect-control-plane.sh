#!/usr/bin/env bash
# Approved authenticated read-only metadata. No secret values or access changes.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -p "$OUT"
az extension show --name azure-firewall -o json > "$OUT/firewall-cli-extension.json" || { printf 'Missing preapproved azure-firewall CLI extension.\n' >&2; exit 2; }
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
date -u +%FT%TZ > "$OUT/time-utc.txt"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network firewall show -g "$RG" -n lab-firewall -o json > "$OUT/firewall.json"
az_read network firewall policy show -g "$RG" -n lab-policy -o json > "$OUT/policy-reference-metadata.json"
az_read network firewall policy rule-collection-group list -g "$RG" --policy-name lab-policy -o json > "$OUT/rule-groups.json"
az_read monitor diagnostic-settings list --resource "$FW_ID" -o json > "$OUT/firewall-diagnostics.json"
az_read network nic show -g "$RG" -n app-nic -o json > "$OUT/app-nic.json"
az_read network nic show-effective-route-table -g "$RG" -n app-nic -o json > "$OUT/effective-routes.json"
az_read network nic list-effective-nsg -g "$RG" -n app-nic -o json > "$OUT/effective-nsg.json"
az_read network vnet subnet show -g "$RG" --vnet-name app -n workload -o json > "$OUT/app-subnet.json"
az_read network vnet show -g "$RG" -n app -o json > "$OUT/app-vnet-dns.json"
for vnet in hub app; do az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"; done
az_read webapp show -g "$RG" -n "$ORIGIN" --query '{id:id,name:name,state:state,defaultHostName:defaultHostName,httpsOnly:httpsOnly}' -o json > "$OUT/origin.json"
az_read webapp config show -g "$RG" -n "$ORIGIN" -o json > "$OUT/origin-config.json"
az_read webapp config access-restriction show -g "$RG" -n "$ORIGIN" -o json > "$OUT/origin-access-restrictions.json"
# No appsettings, publishing profiles, access tokens or Key Vault secret reads.
printf 'Configuration metadata collected: %s. No TLS, CA retrieval or origin readiness inferred.\n' "$OUT"
