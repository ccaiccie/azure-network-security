#!/usr/bin/env bash
# Operator-run on an authorized management workstation after deployment.
# Reads Azure configuration/diagnostics only; never applies Terraform or starts a VM.
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-"$ROOT/evidence/control-plane-$(date -u +%Y%m%dT%H%M%SZ)"}
for tool in terraform az python3; do
  command -v "$tool" >/dev/null || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 2; }
done
mkdir -p "$OUT"
terraform -chdir="$ROOT" output -json > "$OUT/terraform-outputs.json"
read_output() {
  python3 - "$OUT/terraform-outputs.json" "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]]["value"])
PY
}
RG=$(read_output resource_group_name)
VM=$(read_output vm_name)
VM_ID=$(read_output vm_id)
NIC=$(read_output nic_name)
FW=$(read_output firewall_name)
FW_ID=$(read_output firewall_id)
POLICY_ID=$(read_output firewall_policy_id)
SUBSCRIPTION=$(printf '%s' "$VM_ID" | cut -d/ -f3)
az_for_subscription() { az "$@" --subscription "$SUBSCRIPTION"; }
AZ=(az_for_subscription)

printf '%s\n' "$(date -u +%FT%TZ)" > "$OUT/time-utc.txt"
"${AZ[@]}" account show --query '{subscription:id,tenant:tenantId,name:name}' -o json > "$OUT/account.json"
"${AZ[@]}" network firewall show -g "$RG" -n "$FW" -o json > "$OUT/firewall.json"
"${AZ[@]}" network public-ip list -g "$RG" -o json > "$OUT/public-ips.json"
"${AZ[@]}" network nic show -g "$RG" -n "$NIC" -o json > "$OUT/nic.json"
"${AZ[@]}" network nic show-effective-route-table -g "$RG" -n "$NIC" -o json > "$OUT/effective-routes.json"
"${AZ[@]}" network nic list-effective-nsg -g "$RG" -n "$NIC" -o json > "$OUT/effective-nsg.json"
"${AZ[@]}" network vnet peering list -g "$RG" --vnet-name vnet-hub -o json > "$OUT/peering-hub.json"
"${AZ[@]}" network vnet peering list -g "$RG" --vnet-name vnet-spoke -o json > "$OUT/peering-spoke.json"
"${AZ[@]}" network vnet subnet show -g "$RG" --vnet-name vnet-spoke -n snet-workload -o json > "$OUT/subnet-workload.json"
"${AZ[@]}" network route-table show -g "$RG" -n rt-spoke-egress -o json > "$OUT/route-table.json"
"${AZ[@]}" resource show --ids "$POLICY_ID" -o json > "$OUT/policy.json"
"${AZ[@]}" network firewall policy rule-collection-group show -g "$RG" --policy-name policy-egress -n rcg-egress-demo -o json > "$OUT/rule-collection-group.json"
"${AZ[@]}" monitor diagnostic-settings list --resource "$FW_ID" -o json > "$OUT/diagnostics.json"
"${AZ[@]}" vm get-instance-view -g "$RG" -n "$VM" -o json > "$OUT/vm-instance-view.json"
"${AZ[@]}" resource list -g "$RG" -o json > "$OUT/resources.json"
printf 'Collected read-only control-plane evidence in %s\n' "$OUT"
printf 'Guest tests and Log Analytics queries are separate. No traffic success is inferred here.\n'
