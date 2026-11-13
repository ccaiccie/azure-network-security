#!/usr/bin/env bash
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid approved UUID.\n' >&2; exit 2; }
  for tool in terraform python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  read_optional_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],{}).get("value"))' "$1"; }
  read_map_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"][sys.argv[2]])' "$1" "$2"; }
  python3 - "$TF_OUTPUTS" "$SUBSCRIPTION_ID" <<'PY'
import json,re,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower();rg=v.get('resource_group_name')
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or state absent')
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid RG')
base=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/';network=base+'Microsoft.Network/'
expected={'hub_id':network+'virtualHubs/spp-hub','vwan_id':network+'virtualWans/lab-wan','connection_id':network+'virtualHubs/spp-hub/hubVirtualNetworkConnections/connect-app','hub_default_route_table_id':network+'virtualHubs/spp-hub/hubRouteTables/defaultRouteTable','vpn_gateway_id':network+'vpnGateways/spp-vpn-gateway','management_vnet_id':network+'virtualNetworks/management'}
for k,want in expected.items():
 if not isinstance(v.get(k),str) or v[k].lower()!=want.lower():raise SystemExit('Unexpected scoped resource ID: '+k)
if v.get('hub_name')!='spp-hub' or v.get('vpn_gateway_name')!='spp-vpn-gateway':raise SystemExit('Unexpected resource name')
if v.get('spp_id') is not None and v['spp_id'].lower()!=(network+'securityPartnerProviders/spp-zscaler').lower():raise SystemExit('Unexpected SPP ID')
for role in ['origin1','origin2']:
 if v.get('origin_public_ip_ids',{}).get(role,'').lower()!=(network+'publicIPAddresses/'+role+'-public-ip').lower():raise SystemExit('Unexpected origin PIP ID')
for role in ['app','origin1','origin2']:
 if v.get('vm_ids',{}).get(role,'').lower()!=(base+'Microsoft.Compute/virtualMachines/'+role).lower():raise SystemExit('Unexpected VM ID')
nics=v.get('nic_ids')
if not isinstance(nics,dict) or set(nics)!={'app','origin1','origin2'}:raise SystemExit('Unexpected NIC ID map')
for role,value in nics.items():
 if not isinstance(value,str) or value.lower()!=(network+'networkInterfaces/'+role+'-nic').lower():raise SystemExit('Unexpected scoped NIC ID: '+role)
PY
  RG=$(read_output resource_group_name)
  HUB=$(read_output hub_name)
  HUB_ID=$(read_output hub_id)
  GATEWAY_ID=$(read_output vpn_gateway_id)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
require_extensions() {
  command -v az >/dev/null || return 2
  local ext
  for ext in "$@"; do az extension show --name "$ext" --query name -o tsv >/dev/null || { printf 'Missing approved extension %s; no install attempted.\n' "$ext" >&2; return 2; }; done
}
