#!/usr/bin/env python3
"""Source contract smoke checks, NOT Terraform/HCL/provider/service validation."""
import ast,base64,gzip,re,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1];N=0
def rd(p):
 # terraform fmt aligns '=' with several spaces; collapse them so the text checks below stay valid
 return re.sub(r'[ \t]+=[ \t]+',' = ',p.read_text())
def check(condition,message):
 global N
 assert condition,message
 N+=1
def has(path,*snippets):
 text=rd((R/path))
 for s in snippets:check(s in text,str(path)+': '+s)
 return text
for path in list(R.glob('*.tf'))+list((R/'module').glob('*.tf'))+list((R/'tests').glob('*.tftest.hcl')):
 text=rd(path);check(not re.search(r'=\s+=',text),str(path)+': equality')
 clean=re.sub(r'"(?:\\.|[^"\\])*"|#[^\n]*|//[^\n]*','',text);stack=[]
 for char in clean:
  if char in '{[(':stack.append(char)
  elif char in '}])':assert stack and stack.pop()=={'}':'{',']':'[',')':'('}[char],str(path)+': delimiters'
 check(not stack,str(path)+': unclosed delimiter')
check(rd((R/'variables.tf'))==rd((R/'module/variables.tf')),'validation parity')
v=rd((R/'variables.tf'))
for gate in ['deploy_lab','image_prerequisites_confirmed','identity_access_authorized','pe_ready','dns_enabled','dns_verified','routes_verified','pe_ingress_enabled','client_paths_enabled','seed_paths_enabled','allow_client_blob','allow_seed_blob','grant_reader_role','grant_seed_role','isolation_verified','route_experiment_acknowledged']:
 block=v.split(f'variable "{gate}" {{')[1].split('\nvariable ',1)[0];check('default = false' in block and 'nullable = false' in block,'false '+gate)
has('variables.tf','var.image_prerequisites_confirmed && var.identity_access_authorized','"NetworkSecurityGroupEnabled"','"RouteTableEnabled"','!var.allow_seed_blob','var.install_pe_host_route')
has('module/main.tf','reader = "10.10.1.10", seed = "10.10.1.11"','client-to-endpoint','endpoint-to-client','management-to-client','private_endpoint_network_policies = var.pe_network_policies','default_outbound_access_enabled = false')
has('module/routes.tf','address_prefix = "${local.endpoint_ip}/32"','next_hop_type = "None"','bgp_route_propagation_enabled = false','subnet_id = azurerm_subnet.client.id')
routes=rd((R/'module/routes.tf'));check(routes.count('resource "azurerm_route_table"')==1,'only client route table');check('subnet_id = azurerm_subnet.firewall' not in routes,'no recursive Firewall table')
has('module/storage.tf','public_network_access = "Disabled"','shared_access_key_enabled = false','allow_nested_items_to_be_public = false','https_traffic_only_enabled = true','container_access_type = "private"','resolution_policy = "Default"','private_dns_zone_id = azurerm_private_dns_zone.blob.id','virtual_network_id = azurerm_virtual_network.lab["hub"].id','subresource_names = ["blob"]','member_name = "blob"','private_ip_address = local.endpoint_ip','scope = azurerm_storage_container.lab.id','Storage Blob Data Reader','Storage Blob Data Contributor','principal_id = azurerm_linux_virtual_machine.client[each.key].identity[0].principal_id')
has('module/firewall.tf','name = "pe-policy"','name = "blob-rules"','priority = 200','proxy_enabled = true','source_addresses = ["${application_rule_collection.value}/32"]','destination_fqdns = [local.blob_fqdn]','type = "Https"','port = 443')
fw=rd((R/'module/firewall.tf'));check('network_rule_collection {' not in fw and 'nat_rule_collection {' not in fw,'application only')
check('target_fqdns' not in fw and 'destination_fqdns' in fw,'policy application rule uses correct destination_fqdns schema')
has('module/security.tf','priority = 100','priority = 110','Udp = 200, Tcp = 201','priority = 210','priority = 220','priority = 4000','destination_address_prefix = "AzurePlatformIMDS"','name = "platform-imds"','Cloud-init needs host-local IMDS metadata at boot','source_address_prefix = "10.0.1.0/26"','ip_forwarding_enabled = false','dns_servers = [azurerm_firewall.lab.ip_configuration[0].private_ip_address]')
has('module/compute.tf','identity { type = "SystemAssigned" }','package_update = false','package_upgrade = false','source_image_id = var.image_id','base64gzip(file(')
for ref in re.findall(r'file\("\$\{path.module\}/\.\./([^"\n]+)"\)',rd((R/'module/compute.tf'))):check((R/ref).is_file(),'cloud-init source '+ref)
alltf='\n'.join(rd(p) for p in (R/'module').glob('*.tf'));resources={f'{a}.{b}' for a,b in re.findall(r'resource\s+"([^"]+)"\s+"([^"]+)"',alltf)};refs=set(re.findall(r'\b(azurerm_[a-z0-9_]+\.[a-z0-9_]+)\b',alltf));check(not refs-resources,'no dangling resource references')
for absent in ['resource "azurerm_storage_blob"','resource "tls_private_key"','resource "azurerm_nat_gateway"','service_endpoints =','public_ip_address_id =']:
 text=rd((R/'module/compute.tf'))+rd((R/'module/security.tf')) if absent=='public_ip_address_id =' else alltf
 check(absent not in text,'excluded '+absent)
has('guest/probe.py',"If-None-Match",'CERT_REQUIRED','server_hostname=',"conn.auto_open=0",'Metadata','https%3A%2F%2Fstorage.azure.com%2F','response.status==200 and body==PAYLOAD','response.status==201','write_json(out/\'attempt.json\'','private_path_proven\':False','firewall_inspection_proven\':False','Class/stage only','Symlink output path component refused')
has('scripts/common.sh','--subscription "$SUBSCRIPTION_ID"','Unexpected conditional role ID map','identity_principal_ids','Invalid subscription UUID')
has('scripts/collect-control-plane.sh','PRIVATE-HANDLING-REQUIRED.txt','completed_utc=','blob_access_verification=NOT_PERFORMED','No PE NIC effective-route/security','complete API response receipt')
payload=(R/'fixtures/proof.txt').read_bytes()
check(len(payload)==51,'fixed synthetic bytes')
check(hashlib.sha256(payload).hexdigest()=='003da15a8a946410c90f1216eb109b19e40ba6b307fee105d277cb43cc07e8e0','fixed synthetic hash')
node=next(n for n in ast.parse((R/'guest/probe.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='PAYLOAD' for t in n.targets))
check(ast.literal_eval(node.value)==payload,'helper and fixture byte parity')
size=sum(len(base64.b64encode(gzip.compress((R/p).read_bytes()))) for p in ['guest/probe.py','scripts/pe-probe','scripts/pe-ready'])+8192
check(size<65536,'compressed source estimate below64KiB, not rendered custom data')
has('README.md','verify reader NIC closure before reviewing the first reachability result or proceeding to any token-bearing operation')
print(f'PASS {N} source assertions; compressed sources plus8192-byte reserve={size} bytes, not Terraform-rendered payload.')
print('No HCL semantics, provider schema, real TLS/DNS/token/Blob authorization or Azure execution verified.')
