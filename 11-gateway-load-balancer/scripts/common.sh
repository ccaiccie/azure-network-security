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
  read_map_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"][sys.argv[2]])' "$1" "$2"; }
  python3 - "$TF_OUTPUTS" "$SUBSCRIPTION_ID" <<'GUARD'
import json,re,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower();rg=v.get('resource_group_name')
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or state absent')
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid RG')
base=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/';net=base+'Microsoft.Network/'
expected={'gwlb_id':net+'loadBalancers/inspection-gwlb','consumer_lb_id':net+'loadBalancers/public-lb','gwlb_frontend_id':net+'loadBalancers/inspection-gwlb/frontendIPConfigurations/inspection-frontend','consumer_frontend_id':net+'loadBalancers/public-lb/frontendIPConfigurations/public-frontend','consumer_public_ip_id':net+'publicIPAddresses/consumer-public-ip','nva_pool_id':net+'loadBalancers/inspection-gwlb/backendAddressPools/nva-pool','app_pool_id':net+'loadBalancers/public-lb/backendAddressPools/app-pool','bastion_id':net+'bastionHosts/management-bastion'}
for k,want in expected.items():
 if not isinstance(v.get(k),str) or v[k].lower()!=want.lower():raise SystemExit('Unexpected scoped ID: '+k)
for key,roles,prefix,suffix in [('vm_ids',{'app','nva1','nva2'},base+'Microsoft.Compute/virtualMachines/',''),('nic_ids',{'app','nva1','nva2'},net+'networkInterfaces/','-nic'),('vnet_ids',{'provider','consumer','management'},net+'virtualNetworks/','')]:
 value=v.get(key)
 if not isinstance(value,dict) or set(value)!=roles:raise SystemExit('Unexpected ID map: '+key)
 for role,actual in value.items():
  if not isinstance(actual,str) or actual.lower()!=(prefix+role+suffix).lower():raise SystemExit('Unexpected map target: '+key+'/'+role)
probes=v.get('probe_ids');want={'nva':net+'loadBalancers/inspection-gwlb/probes/nva-readiness','app':net+'loadBalancers/public-lb/probes/app-readiness'}
if not isinstance(probes,dict) or set(probes)!=set(want) or any(not isinstance(probes[k],str) or probes[k].lower()!=want[k].lower() for k in want):raise SystemExit('Unexpected probe IDs')
if v.get('bastion_name')!='management-bastion' or v.get('gwlb_frontend_private_ip')!='10.0.2.10' or v.get('backend_private_ip')!='10.20.1.20':raise SystemExit('Unexpected fixed identity')
GUARD
  RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
require_extensions() {
  command -v az >/dev/null || return 2
  local ext
  for ext in "$@"; do az extension show --name "$ext" --query name -o tsv >/dev/null || { printf 'Missing already-approved extension %s; no installation attempted.\n' "$ext" >&2; return 2; }; done
}
