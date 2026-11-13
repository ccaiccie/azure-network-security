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
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};sub=sys.argv[2].lower();rg=v.get('resource_group_name');account=v.get('storage_account_name')
if v.get('deployment_enabled') is not True:raise SystemExit('Deployment disabled or state absent')
if not isinstance(rg,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{1,88}[A-Za-z0-9]',rg):raise SystemExit('Invalid resource group')
if not isinstance(account,str) or not re.fullmatch(r'[a-z0-9]{3,24}',account):raise SystemExit('Invalid storage name')
base=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/';net=base+'Microsoft.Network/';storage=base+'Microsoft.Storage/storageAccounts/'+account;container=storage+'/blobServices/default/containers/lab-data'
def check(key,actual,want):
 if not isinstance(actual,str) or actual.lower()!=want.lower():raise SystemExit('Unexpected scoped identity: '+key)
for key,want in {'firewall_id':net+'azureFirewalls/hub-firewall','firewall_policy_id':net+'firewallPolicies/pe-policy','workspace_id':base+'Microsoft.OperationalInsights/workspaces/pe-logs','bastion_id':net+'bastionHosts/management-bastion','endpoint_id':net+'privateEndpoints/blob-pe','endpoint_subnet_id':net+'virtualNetworks/endpoint/subnets/private-endpoints','endpoint_nsg_id':net+'networkSecurityGroups/endpoint-nsg','route_table_id':net+'routeTables/client-pe-inspection','storage_account_id':storage,'container_id':container,'private_dns_zone_id':net+'privateDnsZones/privatelink.blob.core.windows.net'}.items():check(key,v.get(key),want)
maps={
 'vm_ids':{k:base+'Microsoft.Compute/virtualMachines/'+k for k in ['reader','seed']},
 'nic_ids':{k:net+'networkInterfaces/'+k+'-nic' for k in ['reader','seed']},
 'vnet_ids':{k:net+'virtualNetworks/'+k for k in ['hub','client','endpoint','management']},
}
for key,want in maps.items():
 actual=v.get(key)
 if not isinstance(actual,dict) or set(actual)!=set(want):raise SystemExit('Unexpected ID map: '+key)
 for role,value in actual.items():check(key+'/'+role,value,want[role])
if v.get('private_ips')!={'reader':'10.10.1.10','seed':'10.10.1.11'} or v.get('endpoint_ip')!='10.30.1.7' or v.get('bastion_name')!='management-bastion' or v.get('firewall_name')!='hub-firewall':raise SystemExit('Unexpected fixed identities')
if v.get('container_name')!='lab-data' or v.get('blob_name')!='proof.txt' or v.get('blob_fqdn')!=account+'.blob.core.windows.net' or v.get('blob_url')!='https://'+account+'.blob.core.windows.net/lab-data/proof.txt':raise SystemExit('Unexpected exact Blob destination')
uuid=r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
identities=v.get('identity_principal_ids');grants=v.get('role_grants');roles=v.get('role_assignment_ids')
if not isinstance(identities,dict) or set(identities)!={'reader','seed'} or not all(isinstance(x,str) and re.fullmatch(uuid,x) for x in identities.values()) or len(set(x.lower() for x in identities.values()))!=2:raise SystemExit('Unexpected distinct system identity map')
if not isinstance(grants,dict) or set(grants)!={'reader','seed'} or any(type(x)!=bool for x in grants.values()):raise SystemExit('Missing role grant stages')
if not isinstance(roles,dict) or set(roles)!={k for k,val in grants.items() if val}:raise SystemExit('Unexpected conditional role ID map')
for role,value in roles.items():
 prefix=container+'/providers/Microsoft.Authorization/roleAssignments/'
 if not isinstance(value,str) or not value.lower().startswith(prefix.lower()) or not re.fullmatch(uuid,value[len(prefix):]):raise SystemExit('Unexpected container-scoped role ID')
try:
 f=v.get('firewall_private_ip')
 if not isinstance(f,str):raise ValueError()
 ip=ipaddress.ip_address(f);network=ipaddress.ip_network('10.0.1.0/26')
 if ip.version!=4 or str(ip)!=f or ip not in network or int(ip)-int(network.network_address)<4 or ip==network.broadcast_address:raise ValueError()
except (TypeError,ValueError):raise SystemExit('Unexpected allocated Firewall IPv4')
GUARD
 RG=$(read_output resource_group_name)
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
