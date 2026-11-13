#!/usr/bin/env python3
"""Source-text invariants, NOT an HCL parser/provider/runtime validation."""
import ast,base64,gzip,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];COUNT=0

def need(condition,message):
 global COUNT
 COUNT+=1
 if not condition:raise AssertionError(message)

def norm(t,path=''):
 return re.sub(r'[ \t]+=[ \t]+',' = ',t) if str(path).endswith(('.tf','.hcl')) else t  # terraform fmt aligns '='; compare with single spaces
def text(path):return norm((ROOT/path).read_text(),path)

def block(source,kind,name):
 marker=f'{kind} "{name}"'
 start=source.index(marker);op=source.index('{',start);depth=0;quote=False;escape=False;comment=False
 for i in range(op,len(source)):
  c=source[i]
  if comment:
   if c=='\n':comment=False
   continue
  if quote:
   if escape:escape=False
   elif c=='\\':escape=True
   elif c=='"':quote=False
   continue
  if c=='#':comment=True
  elif c=='"':quote=True
  elif c=='{':depth+=1
  elif c=='}':
   depth-=1
   if depth==0:return source[op+1:i]
 raise AssertionError('Unclosed source block: '+marker)

def resource(path,kind,name):return block(text(path),f'resource "{kind}"',name)
all_tf='\n'.join(norm(p.read_text(),p) for p in ROOT.rglob('*.tf'))
for p in sorted(ROOT.rglob('*.tf')):
 t=p.read_text();need(not re.search(r'=\s+=',t),str(p)+' doubled assignment');need(t.count('{')==t.count('}'),str(p)+' simple brace balance')
for name in ['subscription_id','resource_group_name','location','image_id','ssh_public_key']:
 need(f'variable "{name}"' in text('variables.tf'),'Required input '+name)
need(text('variables.tf')==text('module/variables.tf'),'Root/module input contract identical')
for gate in ['deploy_lab','image_prerequisites_confirmed','create_connections','connections_ready','private_routes_verified','fixtures_ready','test_paths_enabled','allow_test_flow']:
 b=block(text('variables.tf'),'variable',gate);need(re.search(r'default\s*=\s*false',b),'Safe default '+gate);need('type = bool' in b,'Boolean '+gate);need('nullable = false' in b,'Non-null '+gate)
need('count = var.deploy_lab ? 1 : 0' in text('main.tf'),'Root disabled empty state')
psk=block(text('variables.tf'),'variable','vpn_shared_key')
for s in ['sensitive = true','default = null','nullable = true','32,128','var.create_connections']:
 need(s in psk,'PSK contract '+s)
for f in ['outputs.tf','module/outputs.tf','terraform.tfvars.example','module/compute.tf']:
 need(not re.search(r'(?:value|shared_key|vpn_shared_key)\s*=\s*(?:var\.vpn_shared_key|"[^"]+")',text(f)),f+' no supplied PSK/output/default assignment')
need('var.create_connections ? can(regex' in psk and ': var.vpn_shared_key == null' in psk,'PSK is rejected while connections are disabled')
need('random_password' not in all_tf and 'tls_private_key' not in all_tf,'No credential generation')
need('version = "= 5.12.0"' in text('versions.tf'),'Provider pin')
need('resource_provider_registrations = "none"' in text('versions.tf'),'No auto registration')
need('prevent_deletion_if_contains_resources = true' in text('versions.tf'),'Dedicated RG guard')
gw=resource('module/gateways.tf','azurerm_virtual_network_gateway','lab')
for s in ['type = "Vpn"','vpn_type = "RouteBased"','sku = "VpnGw1AZ"','generation = "Generation1"','active_active = false','bgp_enabled = false']:
 need(s in gw,'Gateway contract '+s)
need(gw.count('ip_configuration {')==1,'One config for active-standby')
pip=resource('module/gateways.tf','azurerm_public_ip','gateway')
for s in ['sku = "Standard"','allocation_method = "Static"','zones = ["1", "2", "3"]']:need(s in pip,'Gateway PIP '+s)
conn=resource('module/gateways.tf','azurerm_virtual_network_gateway_connection','lab')
for s in ['var.create_connections ?','hub-to-branch','branch-to-hub','type = "Vnet2Vnet"','peer_virtual_network_gateway_id','shared_key = var.vpn_shared_key','bgp_enabled = false','azurerm_subnet_route_table_association.gateway']:
 need(s in conn,'Reciprocal connections '+s)
for forbidden in ['azurerm_local_network_gateway','azurerm_virtual_wan','azurerm_route_server','azurerm_nat_gateway','express_route_circuit','application_rule_collection','nat_rule_collection','random_password','ipsec_policy {','traffic_selector_policy {']:
 need(forbidden not in all_tf,'No unrelated/unsupported resource '+forbidden)
rtg=resource('module/routes.tf','azurerm_route_table','gateway');rtb=resource('module/routes.tf','azurerm_route_table','branch');rts=resource('module/routes.tf','azurerm_route_table','spoke')
need(rtg.count('route {')==1 and '"10.20.0.0/16"' in rtg,'Exact GatewaySubnet spoke route only')
need('bgp_route_propagation_enabled = true' in rtg and '"0.0.0.0/0"' not in rtg,'Gateway propagation and no default')
need('next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address' in rtg,'Dynamic allocated F gateway route')
need(rtb.count('route {')==1 and 'bgp_route_propagation_enabled = true' in rtb and 'next_hop_type = "None"' in rtb,'Branch propagation + discard only')
need(rts.count('route {')==2 and '"172.16.0.0/16"' in rts and 'bgp_route_propagation_enabled = false' in rts,'Exact branch return + suppression')
need('next_hop_in_ip_address = azurerm_firewall.lab.ip_configuration[0].private_ip_address' in rts,'Dynamic F return')
need('azurerm_subnet.gateway["hub"].id' in resource('module/routes.tf','azurerm_subnet_route_table_association','gateway'),'Only hubGateway associated')
need('subnet_id = azurerm_subnet.firewall.id' not in text('module/routes.tf'),'No firewall subnet UDR')
need('azurerm_subnet.gateway' not in text('module/security.tf')+text('module/management.tf'),'No GatewaySubnet NSG')
for name,transit,remote in [('hub_to_spoke','true','false'),('spoke_to_hub','false','true')]:
 p=resource('module/main.tf','azurerm_virtual_network_peering',name)
 for s in ['allow_forwarded_traffic = true',f'allow_gateway_transit = {transit}',f'use_remote_gateways = {remote}']:need(s in p,'Transit '+name+s)
mg=resource('module/main.tf','azurerm_virtual_network_peering','management')
for s in ['allow_forwarded_traffic = false','allow_gateway_transit = false','use_remote_gateways = false']:need(s in mg,'Management isolation '+s)
for s in ['172.16.10.10','10.20.1.20','172.16.250.0/26','10.40.2.0/26','10.0.254.0/26','172.16.254.0/26','management-to-hub','management-to-spoke']:need(s in text('module/main.tf'),'Topology '+s)
fw=text('module/firewall.tf')
for s in ['sku_name = "AZFW_VNet"','sku_tier = "Standard"','name = "hybrid-policy"','name = "hybrid-rules"','name = "deny-healthy-alternate"','name = "deny-reverse-new"','name = "test-flow"','name = "deny-branch-alt-8081"','name = "deny-spoke-new-8082"','name = "branch-to-spoke-8080"','action = local.test_firewall_action']:
 need(s in fw,'Firewall '+s)
need(fw.count('network_rule_collection {')==3 and fw.count('action = "Deny"')==2,'Three collections with stable negative Deny')
need('private_ip_address = "10.0.1.4"' not in all_tf,'No assumed allocation F')
sec=text('module/security.tf')
for s in ['priority = 110','priority = 200','priority = 4000','source_address_prefix = each.value.bastion','destination_address_prefix = "AzurePlatformDNS"','ip_forwarding_enabled = false','private_ip_address_allocation = "Static"']:
 need(s in sec,'NSG/NIC '+s)
need('public_ip_address_id' not in sec,'No public VM NIC')
need('default_outbound_access_enabled = false' in text('module/main.tf'),'No workload default outbound')
compute=text('module/compute.tf')
for rel in ['fixtures/server.py','guest/probe.py','scripts/hybrid-probe','scripts/hybrid-ready','fixtures/azure-hybrid-fixture@.service']:
 need((ROOT/rel).exists(),'Cloud-init file exists '+rel);need('../'+rel in compute,'Delivered '+rel)
need(compute.count('encoding = "gz+b64"')==5,'Compressed source delivery')
for s in ['package_update = false','package_upgrade = false','disable_password_authentication = true','each.key == "branch"','azure-hybrid-fixture@8080.service','azure-hybrid-fixture@8081.service','azure-hybrid-fixture@8082.service']:need(s in compute,'VM fixture '+s)
need('RestrictAddressFamilies=AF_INET AF_UNIX AF_NETLINK' in text('fixtures/azure-hybrid-fixture@.service'),'Allow startup read-only netlink with empty capabilities')
need('local_authentication_enabled = false' in text('module/diagnostics.tf'),'Workspace local auth off, state still sensitive')
for s in ['AZFWNetworkRule','AZFWThreatIntel','GatewayDiagnosticLog','TunnelDiagnosticLog','RouteDiagnosticLog','log_analytics_destination_type = "Dedicated"']:need(s in text('module/diagnostics.tf'),'Structured log '+s)
common=text('scripts/common.sh');collect=text('scripts/collect-control-plane.sh')
for s in ['SUBSCRIPTION_ID','deployment_enabled','connection_ids','gateway_ids','nic_ids','vm_ids','vnet_ids','route_table_ids','bastion_ids','connections_enabled']:
 need(s in common,'Scoped guard '+s)
for s in ['--acknowledge-sensitive-connection-response','connections-SKIPPED.txt','connections-NOT-ENABLED.txt','PRIVATE-HANDLING-REQUIRED.txt','completed_utc=','route_verification=NOT_PERFORMED','inspection_verification=NOT_PERFORMED']:
 need(s in collect,'Collector evidence '+s)
need('ACK=false' in collect,'Connection GET default off')
need('mkdir -- "$OUT"' in collect and 'mkdir -p -- "$OUT"' not in collect,'No evidence clobber')
need('get-shared-key' not in collect and 'terraform show' not in collect and '--debug' not in collect,'No secret retrieval command')
fixture=text('fixtures/server.py');probe=text('guest/probe.py')
for s in ['TCPServer.server_bind(self)','LOCAL_FIXTURES_READY','azure-hybrid-fixture-v1','172.16.10.10','10.20.1.20']:need(s in fixture,'Fixture '+s)
for s in ['attempted_local','attempted_destination','completed_utc','NEEDS_REVIEW','source_tuple_preserved_observed','exist_ok=False','O_EXCL','conn.auto_open = 0','SOCKET_TIMEOUT_SECONDS = 5','FRESH_TOTAL_SECONDS = 15']:need(s in probe,'Probe '+s)
need(probe.index('write_json(out / "connection.json"')<probe.index('conn.sock.connect('),'Persist attempted tuple before SYN')
mock=text('tests/baseline.tftest.hcl');runs=re.findall(r'run "([^"]+)"',mock)
need(len(runs)==17,'Seventeen supplied mock plans');need(mock.count('command = plan')==17 and 'command = apply' not in mock,'Plan-only mock file')
need('reject_stale_readiness_during_connection_removal' in mock,'Regression rejects stale connection readiness')
need('isolated_connection_removal_configuration' in mock,'Regression retains isolation substrate during connection removal')
readme=text('README.md')
need(all(s in readme for s in ['connections_ready = false','create_connections = false','vpn_shared_key = null','Keep `deploy_lab=true`','steps1–3 have established and recorded isolation']),'Explicit safe connection-removal sequence')
# Approximation only, not Terraform-rendered cloud-init. Includes 8 KiB structural/config reserve.
compressed=sum(len(base64.b64encode(gzip.compress((ROOT/f).read_bytes(),mtime=0))) for f in ['fixtures/server.py','guest/probe.py','scripts/hybrid-probe','scripts/hybrid-ready','fixtures/azure-hybrid-fixture@.service'])+8192
need(compressed<65535,'Compressed source estimate leaves cloud-init size margin')
print(f'PASS {COUNT} source assertions; {len(runs)} supplied mock plans NOT RUN; compressed cloud-init source estimate {compressed} bytes including 8192-byte reserve.')
print('These are source-text checks, not HCL parsing, Terraform rendering, provider schema, Azure or guest runtime evidence.')
