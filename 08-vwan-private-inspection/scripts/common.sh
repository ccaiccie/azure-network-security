#!/usr/bin/env bash
# Local state reads only; every Azure resource read is explicitly subscription-scoped.
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid approved subscription UUID.\n' >&2; exit 2; }
  for tool in terraform az python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  [[ "$(read_output deployment_enabled)" == True ]] || { printf 'Deployment disabled or state absent.\n' >&2; exit 2; }
  FW_ID=$(read_output firewall_id)
  HUB_ID=$(read_output hub_id)
  SUBSCRIPTION_ID=$(printf '%s' "$SUBSCRIPTION_ID" | tr '[:upper:]' '[:lower:]')
  python3 - "$FW_ID" "$HUB_ID" "$SUBSCRIPTION_ID" <<'PY'
import re,sys
fw,hub,sub=sys.argv[1:]
for value,kind in [(fw,'azureFirewalls'),(hub,'virtualHubs')]:
 m=re.fullmatch(r'/subscriptions/([0-9a-fA-F-]{36})/resourceGroups/([^/]+)/providers/Microsoft.Network/'+kind+r'/([^/]+)',value)
 if not m or m[1].lower()!=sub:raise SystemExit('Invalid resource ID or approved subscription mismatch')
if fw.split('/')[4]!=hub.split('/')[4]:raise SystemExit('Firewall/hub resource groups differ')
PY
  # Every subsequently read ARM ID must belong to this same dedicated RG/subscription.
  python3 - "$TF_OUTPUTS" "$FW_ID" "$HUB_ID" <<'PY_SCOPE'
import json,sys
values=json.loads(sys.argv[1]);fw,hub=sys.argv[2:]
prefix=fw.rsplit('/providers/',1)[0]+'/providers/Microsoft.Network/'
expected={
 'vwan_id': prefix+'virtualWans/lab-wan',
 'firewall_policy_id': prefix+'firewallPolicies/private-policy',
 'routing_intent_id': hub+'/routingIntent/private-inspection',
 'hub_default_route_table_id': hub+'/hubRouteTables/defaultRouteTable',
}
for key,wanted in expected.items():
 actual=values.get(key,{}).get('value')
 if not isinstance(actual,str) or actual.lower()!=wanted.lower():
  raise SystemExit('Unexpected scoped resource ID: '+key)
PY_SCOPE
  RG=$(read_output resource_group_name)
  HUB=$(read_output hub_name)
  [[ "$RG" == "$(printf '%s' "$FW_ID" | cut -d/ -f5)" && "$HUB" == "${HUB_ID##*/}" ]] || { printf 'State name/ID mismatch.\n' >&2; exit 2; }
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
require_extensions() {
  local ext
  for ext in "$@"; do
    az extension show --name "$ext" --query name -o tsv >/dev/null || { printf 'Missing already approved extension: %s. No install attempted.\n' "$ext" >&2; return 2; }
  done
}
