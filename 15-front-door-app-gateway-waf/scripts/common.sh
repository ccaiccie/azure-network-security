#!/usr/bin/env bash
# Read-only context guard. Never read state, plans, secrets or app settings.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
load_context() {
  : "${SUBSCRIPTION_ID:?Set the approved subscription UUID}"
  TF_OUTPUTS=$(cd "$ROOT" && terraform output -json)
  export TF_OUTPUTS SUBSCRIPTION_ID
  python3 - <<'CHECK'
import ipaddress,json,os,re
j=json.loads(os.environ['TF_OUTPUTS']);sub=os.environ['SUBSCRIPTION_ID']
def need(c,m):
 if not c: raise SystemExit(m)
def value(k):
 need(k in j and isinstance(j[k],dict) and 'value' in j[k] and j[k]['value'] is not None,'Missing required output: '+k)
 return j[k]['value']
uuid=r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
need(re.fullmatch(uuid,sub) is not None,'Invalid subscription UUID')
need(value('deployment_enabled') is True,'Lab is not deployed')
rg=value('resource_group_name');need(isinstance(rg,str) and re.fullmatch(r'[A-Za-z][A-Za-z0-9-]{2,62}',rg),'Invalid RG')
base='/subscriptions/'+sub+'/resourceGroups/'+rg+'/providers/'
exact={
'gateway_id':'Microsoft.Network/applicationGateways/regional-gateway',
'gateway_public_ip_id':'Microsoft.Network/publicIPAddresses/gateway-public',
'gateway_subnet_id':'Microsoft.Network/virtualNetworks/gateway/subnets/appgateway',
'gateway_nsg_id':'Microsoft.Network/networkSecurityGroups/gateway-nsg',
'gateway_waf_policy_id':'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/gateway-waf-policy',
'edge_waf_policy_id':'Microsoft.Network/frontDoorWebApplicationFirewallPolicies/wafedgepolicy',
'frontdoor_profile_id':'Microsoft.Cdn/profiles/layered-frontdoor',
'origin_group_id':'Microsoft.Cdn/profiles/layered-frontdoor/originGroups/regional-gateway-group',
'origin_id':'Microsoft.Cdn/profiles/layered-frontdoor/originGroups/regional-gateway-group/origins/regional-gateway-origin',
'security_policy_id':'Microsoft.Cdn/profiles/layered-frontdoor/securityPolicies/owned-edge-security',
'workspace_id':'Microsoft.OperationalInsights/workspaces/waf-observability'}
for key,suffix in exact.items():
 v=value(key);need(isinstance(v,str) and v.lower()==(base+suffix).lower(),'Wrong scoped '+key)
need(value('gateway_name')=='regional-gateway','Wrong gateway name')
bn=value('backend_name');need(isinstance(bn,str) and re.fullmatch(r'[a-z][a-z0-9-]{2,49}[a-z0-9]',bn),'Invalid backend name')
need(value('backend_id').lower()==(base+'Microsoft.Web/sites/'+bn).lower(),'Wrong backend ID')
eid=value('edge_endpoint_id');need(isinstance(eid,str) and re.fullmatch(re.escape(base+'Microsoft.Cdn/profiles/layered-frontdoor/afdEndpoints/')+r'[a-z][a-z0-9-]{2,49}[a-z0-9]',eid,re.I),'Wrong endpoint ID')
need(value('edge_route_id').lower()==(eid+'/routes/owned-https-route').lower(),'Wrong route ID')
for key in ['frontdoor_id','workspace_customer_id']:need(isinstance(value(key),str) and re.fullmatch(uuid,value(key)) is not None,'Invalid '+key)
identity=value('gateway_identity_id');need(isinstance(identity,str) and re.fullmatch(re.escape('/subscriptions/'+sub)+r'/resourceGroups/[a-z0-9._()-]+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[a-z0-9._()-]+',identity,re.I),'Unexpected external identity ID')
for key,suffix in [('edge_fqdn','.azurefd.net'),('backend_fqdn','.azurewebsites.net'),('origin_fqdn',None)]:
 v=value(key);need(isinstance(v,str) and len(v)<=253 and re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}',v),'Invalid '+key)
 if suffix:need(v.endswith(suffix),'Wrong service hostname')
 need(not v.endswith(('.invalid','.example','.localhost')),'Placeholder hostname')
def public(v):
 need(isinstance(v,str),'Address must be a string')
 try: p=ipaddress.ip_address(v)
 except ValueError: raise SystemExit('Invalid IPv4')
 need(p.version==4 and str(p)==v and p.is_global and not (p.is_multicast or p.is_reserved or p.is_unspecified or p.is_loopback),'Address must be actual public unicast IPv4')
 return p
p=public(value('gateway_public_ip'));c=value('operator_cidr');need(isinstance(c,str) and c.endswith('/32'),'Approved client must be /32');public(c[:-3]);need(str(p)!=c[:-3],'Client and gateway must differ')
g=value('gate_state');expected={'deploy_lab','certificate_access_confirmed','origin_dns_verified','fixture_publish_enabled','fixture_ready','backend_access_enabled','backend_health_verified','gateway_ingress_enabled','fdid_diagnostic_ingress_enabled','diagnostic_ingress_authorized','fdid_negative_cases_verified','edge_route_enabled'}
need(isinstance(g,dict) and set(g)==expected and all(type(x)==bool for x in g.values()),'Malformed gate map')
need(type(value('publication_enabled'))==bool and value('publication_enabled')==g['fixture_publish_enabled'],'Mismatched publication gate')
need(g['deploy_lab'] and g['certificate_access_confirmed'],'Missing deployment/certificate attestation')
need(not g['fixture_publish_enabled'] or (not g['edge_route_enabled'] and not g['fdid_diagnostic_ingress_enabled']),'Publication conflicts with reachable test paths')
need(not g['backend_health_verified'] or (g['backend_access_enabled'] and g['fixture_ready']),'Invalid backend readiness gates')
need(not g['fdid_diagnostic_ingress_enabled'] or (g['diagnostic_ingress_authorized'] and g['origin_dns_verified'] and g['backend_health_verified'] and not g['edge_route_enabled'] and not g['fixture_publish_enabled']),'Invalid diagnostic ingress gates')
need(not g['edge_route_enabled'] or (g['gateway_ingress_enabled'] and g['origin_dns_verified'] and g['backend_health_verified'] and g['fdid_negative_cases_verified'] and not g['fdid_diagnostic_ingress_enabled'] and not g['fixture_publish_enabled']),'Invalid published-edge gates')
CHECK
  RG=$(read_output resource_group_name)
  BACKEND=$(read_output backend_name)
  export RG BACKEND
}
read_output() {
  python3 - "$1" <<'READ'
import json,os,sys
v=json.loads(os.environ['TF_OUTPUTS'])[sys.argv[1]]['value']
print(json.dumps(v,separators=(',',':')) if isinstance(v,(dict,list,bool)) else v)
READ
}
az_read() { az "$@" --subscription "$SUBSCRIPTION_ID"; }
