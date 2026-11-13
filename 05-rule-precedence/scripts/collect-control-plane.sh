#!/usr/bin/env bash
# Future approved authenticated reads only, no deployment or secret retrieval.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p -- "$(dirname -- "$OUT")"
if ! mkdir -- "$OUT"; then
  printf 'Evidence path already exists or cannot be created: %s. Choose a new OUT or omit it for a unique directory.\n' "$OUT" >&2
  exit 2
fi
STARTED_UTC=$(date -u +%FT%TZ)
printf 'started_utc=%s\n' "$STARTED_UTC" > "$OUT/timing.txt"
trap 'status=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$status" >> "$OUT/timing.txt"' EXIT
az extension show --name azure-firewall -o json > "$OUT/firewall-extension.json" || { printf 'Install/approve required extension separately; dynamic installation is disabled.\n' >&2; exit 2; }
printf '%s\n' "$TF_OUTPUTS" > "$OUT/terraform-outputs.json"
date -u +%FT%TZ > "$OUT/time-utc.txt"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network firewall show -g "$RG" -n lab-firewall -o json > "$OUT/firewall.json"
az_read network firewall policy show -g "$RG" -n lab-policy -o json > "$OUT/policy.json"
az_read network firewall policy rule-collection-group list -g "$RG" --policy-name lab-policy -o json > "$OUT/rule-groups.json"
az_read monitor diagnostic-settings list --resource "$FW_ID" -o json > "$OUT/firewall-diagnostics.json"
for role in app backend; do
  az_read network nic show -g "$RG" -n "$role-nic" -o json > "$OUT/$role-nic.json"
  az_read network nic show-effective-route-table -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-routes.json"
  az_read network nic list-effective-nsg -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-nsg.json"
  az_read network vnet subnet show -g "$RG" --vnet-name "$role" -n workload -o json > "$OUT/$role-subnet.json"
  az_read network vnet show -g "$RG" -n "$role" -o json > "$OUT/$role-vnet-dns.json"
  az_read network route-table show -g "$RG" -n "$role-inspect" -o json > "$OUT/$role-route-table.json"
done
for vnet in hub app backend; do az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"; done
az_read network private-dns zone show -g "$RG" -n policy.test -o json > "$OUT/private-dns-zone.json"
az_read network private-dns link vnet list -g "$RG" -z policy.test -o json > "$OUT/private-dns-links.json"
az_read network private-dns record-set a list -g "$RG" -z policy.test -o json > "$OUT/private-dns-a-records.json"
printf 'Control-plane evidence saved to %s; no packet or policy outcome inferred.\n' "$OUT"
