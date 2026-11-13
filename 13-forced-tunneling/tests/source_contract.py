#!/usr/bin/env python3
"""Source contract assertions, NOT an HCL parser/provider/kernel test."""
import ast,base64,gzip,re
from pathlib import Path
R=Path(__file__).resolve().parents[1];N=0

def norm(t,path=''):
 return re.sub(r'[ \t]+=[ \t]+',' = ',t) if str(path).endswith(('.tf','.hcl')) else t  # terraform fmt aligns '='

def check(condition,message):
 global N
 assert condition,message
 N+=1

def has(path,*snippets):
 text=norm((R/path).read_text(),path)
 for snippet in snippets:check(norm(snippet,path) in text,str(path)+': '+snippet)
 return text

for path in list(R.glob('*.tf'))+list((R/'module').glob('*.tf'))+list((R/'tests').glob('*.tftest.hcl')):
 text=path.read_text();check(not re.search(r'=\s+=',text),str(path)+': malformed equality')
 # Strip strings/comments only for a balanced-delimiter smoke check, not semantic parsing.
 clean=re.sub(r'"(?:\\.|[^"\\])*"|#[^\n]*|//[^\n]*','',text);stack=[]
 for char in clean:
  if char in '{[(':stack.append(char)
  elif char in '}])':assert bool(stack) and stack.pop()=={'}':'{',']':'[',')':'('}[char],str(path)+': delimiters'
 check(not stack,str(path)+': unclosed delimiters')
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module validation parity')
v=norm((R/'variables.tf').read_text(),'x.tf')
for gate in ['deploy_lab','image_prerequisites_confirmed','fixtures_ready','private_routes_verified','perimeter_ready','origin_access_enabled','test_paths_enabled','allow_test_flow','snat_comparison_acknowledged']:
 block=v.split(f'variable "{gate}" {{',1)[1].split('\nvariable ',1)[0];check('default = false' in block and 'nullable = false' in block,'false gate '+gate)
has('main.tf','count = var.deploy_lab ? 1 : 0','source = "./module"')
has('module/main.tf','"10.0.1.0/26"','"10.0.2.0/26"','"10.20.1.10"','"10.30.1.4"','"10.50.1.20"','"10.40.2.0/26"','default_outbound_access_enabled = false','allow_forwarded_traffic = false','allow_gateway_transit = false','use_remote_gateways = false','var.source_mode == "preserve" ? "10.20.1.10/32" : "10.0.1.0/26"')
has('module/routes.tf','name = "app-forced-default"','name = "firewall-to-perimeter"','name = "perimeter-return"','address_prefix = "10.20.0.0/16"','next_hop_in_ip_address = local.perimeter_ip')
routes=norm((R/'module/routes.tf').read_text(),'x.tf');check(routes.count('bgp_route_propagation_enabled = false')==3,'all three route tables disable propagation');check(routes.count('address_prefix = "0.0.0.0/0"')==2,'only app/data defaults');check('firewall_management' not in routes,'no customer management table')
has('module/firewall.tf','private_ip_ranges = var.source_mode == "preserve" ? ["0.0.0.0/0"] : ["IANAPrivateRanges"]','management_ip_configuration {','public_ip_address_id = azurerm_public_ip.firewall_management.id','name = "deny-app-8081"','destination_ports = ["8080", "8082"]','name = "forced-rules"')
f=norm((R/'module/firewall.tf').read_text(),'x.tf');data=f.split('  ip_configuration {',1)[1].split('  management_ip_configuration',1)[0];check('public_ip_address_id' not in data,'no tenant data public IP')
alltf='\n'.join(norm(p.read_text(),p) for p in (R/'module').glob('*.tf'))
for absent in ['azurerm_virtual_network_gateway','azurerm_vpn','azurerm_route_server','azurerm_nat_gateway','shared_key','tls_private_key']:
 check(absent not in alltf,'no undeclared capability '+absent)
has('module/security.tf','name = "test-transit-ingress", priority = 100','name = "test-translated-egress", priority = 101','name = "test-restored-return", priority = 102','source_ports = local.test_ports, ports = ["*"]','source = "${azurerm_public_ip.endpoint["perimeter"].ip_address}/32"','priority = 110','priority = 200','priority = 4000','ip_forwarding_enabled = each.key == "perimeter"')
has('module/compute.tf','package_update = false','package_upgrade = false','source_image_id = var.image_id','azure-forced-fixture@8082.service','forced-prepare.service','base64gzip(file(')
for ref in re.findall(r'file\("\$\{path.module\}/\.\./([^"\n]+)"\)',(R/'module/compute.tf').read_text()):check((R/ref).is_file(),'cloud-init source '+ref)
has('fixtures/azure-forced-fixture@.service','RestrictAddressFamilies=AF_INET AF_UNIX AF_NETLINK','CapabilityBoundingSet=\n','AmbientCapabilities=\n','DynamicUser=yes')
has('fixtures/server.py','def server_bind(self):','8080, 8081, 8082','azure-forced-origin-v1')
has('guest/controller.py',"TABLE='azure_forced_lab'","type nat hook postrouting priority srcnat",'snat ip to {e}','deny-perimeter-8082-forward','deny-closed-test-forward','nf_conntrack_tcp_loose','SIGHUP','verified-before-finalization','removal_started','phase-not-stable','host {backend.cfg["origin_public_ip"]} and tcp')
for path in ['guest/controller.py','guest/probe.py','fixtures/server.py']:ast.parse((R/path).read_text())
has('scripts/collect-control-plane.sh','--subscription',) if False else None
has('scripts/common.sh','--subscription "$SUBSCRIPTION_ID"','Unexpected ID map','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','isinstance(value,str)')
has('scripts/collect-control-plane.sh','PRIVATE-HANDLING-REQUIRED.txt','completed_utc=','route_verification=NOT_PERFORMED','mkdir -- "$OUT"','client-side')
size=sum(len(base64.b64encode(gzip.compress((R/p).read_bytes()))) for p in ['guest/controller.py','guest/probe.py','fixtures/server.py','fixtures/azure-forced-fixture@.service','guest/forced-prepare.service'])+8192
check(size<65536,'compressed-source estimate with 8192-byte reserve below64KiB; not rendered cloud-init')
print(f'PASS {N} source assertions. Compressed source estimate+reserve={size} bytes; NOT Terraform-rendered payload.')
print('No HCL semantics, provider/schema, kernel policy, service startup or Azure execution verified.')
