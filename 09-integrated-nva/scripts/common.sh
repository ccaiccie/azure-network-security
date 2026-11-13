#!/usr/bin/env bash
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid approved UUID.\n' >&2; exit 2; }
  for tool in terraform python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  read_optional_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],{}).get("value"))' "$1"; }
  python3 - "$TF_OUTPUTS" "$SUBSCRIPTION_ID" <<'PY'
import json,re,sys
v={k:row['value'] for k,row in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower()
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or state missing')
rg=v.get('resource_group_name');hub=v.get('hub_id');prefix=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/'
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid RG')
expected={'hub_id':prefix+'virtualHubs/partner-hub','vwan_id':prefix+'virtualWans/lab-wan','connection_id':prefix+'virtualHubs/partner-hub/hubVirtualNetworkConnections/connect-app','hub_default_route_table_id':prefix+'virtualHubs/partner-hub/hubRouteTables/defaultRouteTable','origin_public_ip_id':prefix+'publicIPAddresses/origin-public-ip','management_vnet_id':prefix+'virtualNetworks/management'}
for k,want in expected.items():
 if not isinstance(v.get(k),str) or v[k].lower()!=want.lower():raise SystemExit('Unexpected scoped ID: '+k)
compute_prefix=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/'
for role in ('app','origin'):
 key=role+'_vm_id';value=v.get(key)
 if not isinstance(value,str) or value.lower()!=(compute_prefix+role).lower():raise SystemExit('Unexpected scoped VM ID: '+key)
nics=v.get('nic_ids')
if not isinstance(nics,dict) or set(nics)!={'app','origin'}:raise SystemExit('Unexpected NIC ID map')
for role,value in nics.items():
 if not isinstance(value,str) or value.lower()!=(prefix+'networkInterfaces/'+role+'-nic').lower():raise SystemExit('Unexpected scoped NIC ID: '+role)
if v.get('hub_name')!='partner-hub':raise SystemExit('Unexpected hub name')
if v.get('routing_intent_id') is not None and v['routing_intent_id'].lower()!=(hub+'/routingIntent/internet-inspection').lower():raise SystemExit('Unexpected intent ID')
p=v.get('vendor_profile')
if (p is None and v.get('nva_resource_id') is not None) or (p is not None and v.get('nva_resource_id')!=p.get('nva_resource_id')):raise SystemExit('NVA output/profile mismatch')
if p is not None:
 for k,kind in [('nva_resource_id','Microsoft.Network/networkVirtualAppliances'),('managed_application_id','Microsoft.Solutions/applications')]:
  value=p.get(k);pattern=r'/subscriptions/([0-9a-fA-F-]{36})/resourceGroups/([^/]+)/providers/'+kind+r'/[^/]+'
  m=re.fullmatch(pattern,value or '')
  if not m or m[1].lower()!=sub:raise SystemExit('Unexpected external profile ID: '+k)
 if p.get('hub_resource_id','').lower()!=hub.lower():raise SystemExit('External NVA profile names wrong hub')
 if p.get('managed_resource_group_id','').lower()!=('/'.join(p['nva_resource_id'].split('/')[:5])).lower():raise SystemExit('NVA is outside profile managed RG')
PY
  RG=$(read_output resource_group_name)
  HUB=$(read_output hub_name)
  HUB_ID=$(read_output hub_id)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
require_extensions() {
  command -v az >/dev/null || return 2
  local ext
  for ext in "$@"; do az extension show --name "$ext" --query name -o tsv >/dev/null || { printf 'Missing approved extension %s; no installation attempted.\n' "$ext" >&2; return 2; }; done
}
