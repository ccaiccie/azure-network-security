#!/usr/bin/env bash
# Management workstation, authenticated read-only evidence. Never deploys or changes Azure.
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
print(json.load(open(sys.argv[1]))[sys.argv[2]]["value"])
PY
}
RG=$(read_output resource_group_name)
FW_ID=$(read_output firewall_id)
SUBSCRIPTION=$(printf '%s' "$FW_ID" | cut -d/ -f3)
az_read() { az "$@" --subscription "$SUBSCRIPTION"; }
date -u +%FT%TZ > "$OUT/time-utc.txt"
az_read account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
az_read network firewall show -g "$RG" -n lab-firewall -o json > "$OUT/firewall.json"
az_read network firewall policy show -g "$RG" -n east-west-policy -o json > "$OUT/policy.json"
az_read network firewall policy rule-collection-group show -g "$RG" --policy-name east-west-policy -n east-west-rules -o json > "$OUT/firewall-rules.json"
az_read monitor diagnostic-settings list --resource "$FW_ID" -o json > "$OUT/diagnostics.json"
mapfile -t ROLES < <(python3 - "$OUT/terraform-outputs.json" <<'PYROLES'
import json,sys
print("\n".join(json.load(open(sys.argv[1]))['workloads']['value'].keys()))
PYROLES
)
for role in "${ROLES[@]}"; do
  read -r VNET SUBNET < <(python3 - "$OUT/terraform-outputs.json" "$role" <<'PYSUBNET'
import json,sys
w=json.load(open(sys.argv[1]))['workloads']['value'][sys.argv[2]]
print(w['vnet_name'],w['subnet_name'])
PYSUBNET
  )
  az_read network nic show -g "$RG" -n "$role-nic" -o json > "$OUT/$role-nic.json"
  az_read network nic show-effective-route-table -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-routes.json"
  az_read network nic list-effective-nsg -g "$RG" -n "$role-nic" -o json > "$OUT/$role-effective-nsg.json"
  az_read network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SUBNET" -o json > "$OUT/$role-subnet.json"
  az_read network route-table show -g "$RG" -n "$role-inspect" -o json > "$OUT/$role-route-table.json"
  az_read vm get-instance-view -g "$RG" -n "$role" -o json > "$OUT/$role-vm.json"
done
for vnet in hub app db; do
  az_read network vnet peering list -g "$RG" --vnet-name "$vnet" -o json > "$OUT/$vnet-peerings.json"
done
az_read resource list -g "$RG" -o json > "$OUT/resources.json"
printf 'Read-only configuration evidence: %s\nNo guest or firewall outcome inferred.\n' "$OUT"
