#!/usr/bin/env bash
set -euo pipefail
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
load_context() {
 : "${SUBSCRIPTION_ID:?Set approved subscription UUID explicitly}"
 [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { printf 'Invalid subscription UUID.\n' >&2; exit 2; }
 TF_OUTPUTS=$(terraform -chdir="$ROOT" output -json)
 read_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1"; }
 read_map_output() { printf '%s' "$TF_OUTPUTS" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]]["value"][sys.argv[2]])' "$1" "$2"; }
 python3 - "$TF_OUTPUTS" "$SUBSCRIPTION_ID" <<'GUARD'
import ipaddress,json,re,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower();rg=v.get('resource_group_name')
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or absent')
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid resource group')
base=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/';net=base+'Microsoft.Network/'
def check(key,actual,want):
 if not isinstance(actual,str) or actual.lower()!=want.lower():raise SystemExit('Unexpected scoped identity: '+key)
for key,want in {'firewall_id':net+'azureFirewalls/hub-firewall','firewall_policy_id':net+'firewallPolicies/forced-policy','workspace_id':base+'Microsoft.OperationalInsights/workspaces/forced-logs','bastion_id':net+'bastionHosts/management-bastion'}.items():check(key,v.get(key),want)
maps={
 'vm_ids':{k:base+'Microsoft.Compute/virtualMachines/'+k for k in ['app','perimeter','origin']},
 'nic_ids':{k:net+'networkInterfaces/'+k+'-nic' for k in ['app','perimeter','origin']},
 'vnet_ids':{k:net+'virtualNetworks/'+k for k in ['hub','app','perimeter','origin','management']},
 'route_table_ids':{k:net+'routeTables/'+name for k,name in {'app':'app-forced-default','firewall':'firewall-to-perimeter','perimeter':'perimeter-return'}.items()},
 'public_ip_ids':{k:net+'publicIPAddresses/'+name for k,name in {'app':'unused','perimeter':'perimeter-public-ip','origin':'origin-public-ip','firewall_management':'firewall-management-public-ip','bastion':'management-bastion-public-ip'}.items() if k!='app'},
}
for key,want in maps.items():
 actual=v.get(key)
 if not isinstance(actual,dict) or set(actual)!=set(want):raise SystemExit('Unexpected ID map: '+key)
 for role,value in actual.items():check(key+'/'+role,value,want[role])
if v.get('private_ips')!={'app':'10.20.1.10','perimeter':'10.30.1.4','origin':'10.50.1.20'} or v.get('bastion_name')!='management-bastion' or v.get('firewall_name')!='hub-firewall':raise SystemExit('Unexpected fixed identity')
mode=v.get('source_mode')
if mode not in ('preserve','firewall_private') or v.get('perimeter_source_prefix')!=('10.20.1.10/32' if mode=='preserve' else '10.0.1.0/26'):raise SystemExit('Unexpected source mode/scope')
try:
 if not isinstance(v.get('firewall_private_ip'),str):raise ValueError()
 f=ipaddress.ip_address(v.get('firewall_private_ip'));s=ipaddress.ip_network('10.0.1.0/26')
 if str(f)!=v['firewall_private_ip']:raise ValueError()
 if f.version!=4 or f not in s or int(f)-int(s.network_address)<4 or f==s.broadcast_address:raise ValueError()
 pool=v.get('public_ips')
 if not isinstance(pool,dict) or set(pool)!= {'perimeter','origin'} or len(set(pool.values()))!=2:raise ValueError()
 for value in pool.values():
  if not isinstance(value,str):raise ValueError()
  ip=ipaddress.ip_address(value)
  if str(ip)!=value:raise ValueError()
  if ip.version!=4 or not ip.is_global or ip.is_multicast or ip.is_reserved or ip in ipaddress.ip_network('192.0.0.0/24') or ip in ipaddress.ip_network('192.88.99.0/24'):raise ValueError()
except (TypeError,ValueError):raise SystemExit('Unexpected actual allocated endpoint/firewall IP')
GUARD
 RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
