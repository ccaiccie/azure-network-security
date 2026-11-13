#!/usr/bin/env python3
"""Source text/AST/brace checks, not HCL/provider/API/ZIA runtime validation."""
import ast,base64,re,struct
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def check(ok,msg):
 global count
 count+=1
 assert ok,msg
def compact(text):
 # Formatting-insensitive textual presence only; not an HCL parser.
 return re.sub(r'\s+','',text)
def has(name,*tokens):
 s=(R/name).read_text()
 is_hcl=name.endswith(('.tf','.tftest.hcl'))
 for t in tokens:check(compact(t) in compact(s) if is_hcl else t in s,f'{name} missing {t}')
for p in R.rglob('*.py'):ast.parse(p.read_text());check(True,'AST '+str(p))
for p in list(R.rglob('*.tf'))+list(R.rglob('*.tftest.hcl')):
 s=p.read_text();check(not re.search(r'=\s+=',s),'corrupt equality '+str(p));check(s.count('{')==s.count('}'),'brace counts '+str(p))
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module validation parity')
has('versions.tf','= 5.12.0','>= 1.11.0','resource_provider_registrations = "none"','prevent_deletion_if_contains_resources = true')
has('module/versions.tf','>= 1.11.0')
mock=(R/'tests/baseline.tftest.hcl').read_text()
check(not re.search(r'\bcommand\s*=\s*apply\b',mock) and len(re.findall(r'\bcommand\s*=\s*plan\b',mock))==13,'thirteen plan-only mocked cases')
has('tests/baseline.tftest.hcl','mock_resource "azurerm_public_ip"','override_during = plan','publicIPAddresses/mock-public-ip','ip_address = "192.0.2.10"','RFC8032-TEST-ONLY-NEVER-DEPLOY')
key=re.search(r'ssh_public_key\s*=\s*"ssh-ed25519 ([^ ]+) ',mock).group(1)
public=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
wire=struct.pack('>I',11)+b'ssh-ed25519'+struct.pack('>I',32)+public
check(base64.b64decode(key,validate=True)==wire,'exact published PUBLIC RFC8032 vector in valid OpenSSH wire format; no generated credential')
has('main.tf','count = var.deploy_lab ? 1 : 0','provider_profile = var.provider_profile')
for gate in ['deploy_lab','image_prerequisites_confirmed','enable_spp','provider_onboarding_verified','tunnels_verified','provider_routing_configured','enable_source_default','protected_routes_verified','fixtures_ready','provider_block_policy_verified','test_paths_enabled']:
 chunk=(R/'variables.tf').read_text().split('variable "'+gate+'" {',1)[1].split('\n}',1)[0];check('default=false' in compact(chunk),'closed gate '+gate)
has('variables.tf','var.provider_profile.provider == "ZScaler"','var.provider_onboarding_verified && var.tunnels_verified && var.provider_routing_configured','var.protected_routes_verified && var.fixtures_ready && var.provider_block_policy_verified','length(var.egress_public_ips) <= 16','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','100.64.0.0/10','approved_scope','azure_principal_object_id')
s=(R/'module/main.tf').read_text();alltf='\n'.join(p.read_text() for p in R.rglob('*.tf'))
for token in ['name = "spp-hub"','address_prefix = "10.0.0.0/23"','name = "spp-vpn-gateway"','scale_unit = var.vpn_scale_unit','count = var.enable_spp ? 1 : 0','security_provider_name = "ZScaler"','depends_on = [azurerm_vpn_gateway.lab]','internet_security_enabled = var.enable_source_default','origin1 = "10.30.1.20", origin2 = "10.30.1.21"','"test-web-egress" : "test-web-ingress"','destination_port_range = "80"','[for pip in azurerm_public_ip.origin : "${pip.ip_address}/32"]','"${each.value.ip}/32"','length(var.egress_public_ips) == 0 ? "*" : null','[for ip in sort(tolist(var.egress_public_ips)) : "${ip}/32"]','default_outbound_access_enabled = false','ip_forwarding_enabled = false','public_ip_address_id = each.key == "app" ? null : azurerm_public_ip.origin[each.key].id']:
 check(compact(token) in compact(s),'required topology '+token)
check(s.count('resource "azurerm_virtual_hub_connection"')==1,'only app connected');check(not re.search(r'\brouting\s*{',s),'no routing ownership conflict')
for forbidden in ['resource "azurerm_virtual_hub_routing_intent"','resource "azurerm_firewall"','resource "azurerm_network_virtual_appliance"','resource "azurerm_vpn_gateway_connection"','resource "azurerm_vpn_site"','resource "azurerm_route_table"','resource "azuread_application"','resource "azurerm_role_assignment"','tls_private_key','shared_key','client_secret','AZFWNetworkRule']:
 check(forbidden not in alltf,'forbidden ownership/secret/substitute '+forbidden)
check(s.count('resource "azurerm_virtual_network_peering"')==2,'management/app peering only');check(compact(s).count('use_remote_gateways=false')==2 and compact(s).count('allow_forwarded_traffic=false')==2 and compact(s).count('allow_gateway_transit=false')==2,'no management default sharing or forwarded transit');check('address_space=["10.40.0.0/16"]' in compact(s) and 'bastion="10.40.2.0/26"' in compact(s),'isolated Bastion network')
has('module/compute.tf','for_each = local.nodes','source_image_id = var.image_id','disable_password_authentication = true','package_update = false','package_upgrade = false','egress_public_ips = []','origins = { for k, ip in local.origins','azure-spp-fixture.service','each.key != "app"','/etc/azure-spp-lab.json')
check('var.egress_public_ips' not in (R/'module/compute.tf').read_text(),'E updates do not replace VM custom_data')
has('module/management.tf','for_each = local.networks','azurerm_virtual_network.management.name','tunneling_enabled      = true')
has('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','--subscription "$SUBSCRIPTION_ID"','Unexpected scoped resource ID','Unexpected SPP ID','Unexpected VM ID','read_optional_output()','Unexpected NIC ID map','Unexpected scoped NIC ID')
has('scripts/collect-control-plane.sh','--resource-type RouteTable','--api-version 2025-07-01 --query','vpn-connections-projected rest --method get','next_link:nextLink','connection_status:properties.connectionStatus','links:properties.vpnLinkConnections','read_optional_output spp_id','vpn-projection-INCOMPLETE.txt','tunnel_verification=NOT_PERFORMED','provider_policy_verification=NOT_PERFORMED','mkdir -- "$OUT"','completed_utc','shell_exit','COLLECT_VPN_CONNECTIONS=false','--acknowledge-full-vpn-response','vpn-connections-SKIPPED.txt','PRIVATE-HANDLING-REQUIRED.txt','without redaction')
collector=(R/'scripts/collect-control-plane.sh').read_text()
for line in collector.splitlines():
 if line.lstrip().startswith('collect ') and ('gateway-projected' in line or 'spp-projected' in line or 'vpn-connections-projected' in line):
  check('--query' in line,'project secret-prone status reads');check(not any(x in line.lower() for x in ['sharedkey','--debug','secret','password']),'no secret fields/debug')
has('scripts/make-runtime-config.sh','os.O_EXCL','0o600','a.is_multicast','1<=len(pool)<=16','e in ds.values()','len(set(ds.values()))!=2')
has('guest/probe.py','attempted_local','attempted_destination','completed_utc','NEEDS_REVIEW','SPP_LAB_CONFIG')
has('.gitignore','!profiles/provider-profile.example.json','spp-plan-*/','spp-review-*/','spp-runtime-*/')
has('fixtures/azure-spp-fixture.service','DynamicUser=yes','CapabilityBoundingSet=CAP_NET_BIND_SERVICE','AmbientCapabilities=CAP_NET_BIND_SERVICE','NoNewPrivileges=yes')
files=['guest/probe.py','fixtures/server.py','scripts/spp-ready','scripts/spp-probe','fixtures/azure-spp-fixture.service'];estimate=sum(4*((len((R/p).read_bytes())+2)//3) for p in files)+8192;check(estimate<65535,'custom-data conservative limit');print(f'Base64 source payload +8KiB metadata reserve: {estimate} bytes; not rendered Terraform custom_data.')
has('README.md','not self-contained','Block','proxy','IPsec','NOT RUN','NEEDS_REVIEW','provider_routing_configured','no universal fail-open/fail-closed','private keys','sharedKey','client-side','omitted from Get/List','--acknowledge-full-vpn-response','without redaction')
print(f'PASS {count} source assertions, including text/brace counts. No HCL/provider/cloud/ZIA validation implied.')
