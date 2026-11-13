#!/usr/bin/env bash
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
  : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid approved subscription UUID.\n' >&2; exit 2; }
  for tool in terraform python3; do command -v "$tool" >/dev/null || exit 2; done
  TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
  read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
  read_map_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"][sys.argv[2]])' "$1" "$2"; }
  python3 - "$TF_OUTPUTS" "$SUBSCRIPTION_ID" <<'GUARD'
import ipaddress,json,re,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower();rg=v.get('resource_group_name')
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or state absent')
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid resource group')
base=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/';net=base+'Microsoft.Network/'
def check(key,actual,want):
 if not isinstance(actual,str) or actual.lower()!=want.lower():raise SystemExit('Unexpected scoped identity: '+key)
for key,want in {'firewall_id':net+'azureFirewalls/hub-firewall','firewall_policy_id':net+'firewallPolicies/hybrid-policy','workspace_id':base+'Microsoft.OperationalInsights/workspaces/hybrid-logs'}.items():check(key,v.get(key),want)
maps={
 'vm_ids':{k:base+'Microsoft.Compute/virtualMachines/'+k for k in ['branch','spoke']},
 'nic_ids':{k:net+'networkInterfaces/'+k+'-nic' for k in ['branch','spoke']},
 'vnet_ids':{k:net+'virtualNetworks/'+k for k in ['hub','branch','spoke','management']},
 'gateway_ids':{k:net+'virtualNetworkGateways/'+k+'-vpn-gateway' for k in ['hub','branch']},
 'gateway_public_ip_ids':{k:net+'publicIPAddresses/'+k+'-vpn-public-ip' for k in ['hub','branch']},
 'route_table_ids':{k:net+'routeTables/'+name for k,name in {'gateway':'gateway-to-spoke','branch':'branch-safety','spoke':'spoke-return'}.items()},
 'bastion_ids':{k:net+'bastionHosts/'+k+'-bastion' for k in ['branch','azure']},
}
if type(v.get('connections_enabled')) is not bool:raise SystemExit('Missing connection stage flag')
# Empty map is required while disabled. Do not silently treat missing/null as healthy or enabled.
maps['connection_ids']={k:net+'connections/'+k for k in ['hub-to-branch','branch-to-hub']} if v['connections_enabled'] else {}
for key,want in maps.items():
 actual=v.get(key)
 if not isinstance(actual,dict) or set(actual)!=set(want):raise SystemExit('Unexpected ID map: '+key)
 for role,value in actual.items():check(key+'/'+role,value,want[role])
if v.get('private_ips')!={'branch':'172.16.10.10','spoke':'10.20.1.20'} or v.get('bastion_names')!={'branch':'branch-bastion','azure':'azure-bastion'}:raise SystemExit('Unexpected fixed identity map')
if v.get('firewall_name')!='hub-firewall':raise SystemExit('Unexpected firewall name')
try:
 ip=ipaddress.ip_address(v.get('firewall_private_ip')); subnet=ipaddress.ip_network('10.0.1.0/26')
 if ip.version!=4 or ip not in subnet or int(ip)-int(subnet.network_address)<4 or ip==subnet.broadcast_address:raise ValueError()
except (TypeError,ValueError):raise SystemExit('Unexpected allocated firewall private IP')
GUARD
  RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
require_extensions() {
  command -v az >/dev/null || return 2
  local ext
  for ext in "$@"; do az extension show --name "$ext" --query name -o tsv >/dev/null || { printf 'Missing already-approved extension %s; no installation attempted.\n' "$ext" >&2; return 2; }; done
}
