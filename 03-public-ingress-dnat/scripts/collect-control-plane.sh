#!/usr/bin/env bash
# Authenticated read-only evidence on management workstation. No mutations.
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-"$ROOT/evidence/control-$(date -u +%Y%m%dT%H%M%SZ)"}
for tool in terraform az python3; do command -v "$tool" >/dev/null || exit 2; done
mkdir -p "$OUT"
terraform -chdir="$ROOT" output -json > "$OUT/terraform-outputs.json"
read_output() {
  python3 - "$OUT/terraform-outputs.json" "$1" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))[sys.argv[2]]['value'])
PY
}
RG=$(read_output resource_group_name); FW_ID=$(read_output firewall_id)
SUBSCRIPTION=$(printf '%s' "$FW_ID" | cut -d/ -f3)
az_read() { az "$@" --subscription "$SUBSCRIPTION"; }
# Suppress Azure CLI's possible first-use extension installation. Require a preapproved copy.
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
if ! az extension show --name azure-firewall -o json > "$OUT/azure-firewall-extension.json"; then
  printf 'Missing approved azure-firewall CLI extension. Stop and arrange authorized installation separately.\n' >&2
  exit 2
fi
date -u +%FT%TZ > "$OUT/time-utc.txt"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network firewall show -g "$RG" -n lab-firewall -o json > "$OUT/firewall.json"
az_read network firewall policy show -g "$RG" -n lab-policy -o json > "$OUT/policy.json"
# List rather than show: correctly captures absence when publish_dnat=false.
az_read network firewall policy rule-collection-group list -g "$RG" --policy-name lab-policy -o json > "$OUT/firewall-rule-groups.json"
az_read monitor diagnostic-settings list --resource "$FW_ID" -o json > "$OUT/diagnostics.json"
az_read network nic show -g "$RG" -n db-nic -o json > "$OUT/db-nic.json"
az_read network nic show-effective-route-table -g "$RG" -n db-nic -o json > "$OUT/db-effective-routes.json"
az_read network nic list-effective-nsg -g "$RG" -n db-nic -o json > "$OUT/db-effective-nsg.json"
az_read network route-table show -g "$RG" -n db-inspect -o json > "$OUT/db-route-table.json"
az_read vm get-instance-view -g "$RG" -n db -o json > "$OUT/db-vm.json"
az_read network vnet subnet show -g "$RG" --vnet-name db -n workload -o json > "$OUT/db-subnet.json"
az_read network vnet subnet show -g "$RG" --vnet-name hub -n AzureFirewallSubnet -o json > "$OUT/firewall-subnet.json"
az_read network vnet subnet show -g "$RG" --vnet-name hub -n AzureBastionSubnet -o json > "$OUT/bastion-subnet.json"
for vnet in hub db; do
  az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"
done
az_read resource list -g "$RG" -o json > "$OUT/resources.json"
printf 'Read-only configuration evidence: %s\nNo guest, source identity, route selection or DNAT success inferred.\n' "$OUT"
