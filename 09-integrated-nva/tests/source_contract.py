#!/usr/bin/env python3
"""Text/AST invariants, NOT HCL parsing or provider/cloud/vendor validation."""
import ast,base64,re,struct
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def check(ok,msg):
 global count
 count+=1
 assert ok,msg
def compact_hcl(text):
 # Text matching only: ignore formatting whitespace outside quoted strings.
 # Quoted values remain exact. This is deliberately not an HCL parser.
 return re.sub(r'"(?:\\.|[^"\\])*"|\s+',lambda m:m[0] if m[0].startswith('"') else '',text)
def has(name,*tokens):
 s=(R/name).read_text()
 if name.endswith(('.tf','.tftest.hcl')):
  for t in tokens:check(compact_hcl(t) in compact_hcl(s),f'{name} missing {t}')
 else:
  for t in tokens:check(t in s,f'{name} missing {t}')
for p in R.rglob('*.py'):ast.parse(p.read_text());check(True,'AST '+str(p))
for p in list(R.rglob('*.tf'))+list(R.rglob('*.tftest.hcl')):
 s=p.read_text();check(not re.search(r'=\s+=',s),'corrupt equality '+str(p));check(s.count('{')==s.count('}'),'brace counts '+str(p))
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module validation parity')
has('versions.tf','"= 5.12.0"','">= 1.11.0, < 2.0.0"','resource_provider_registrations = "none"','prevent_deletion_if_contains_resources = true')
has('module/versions.tf','">= 1.11.0, < 2.0.0"','"= 5.12.0"')
# Passive fixture checks only: decode a published PUBLIC test vector, never create keys.
mock=(R/'tests/baseline.tftest.hcl').read_text()
check(len(re.findall(r'\boverride_during\s*=\s*plan\b',mock))==2,'computed public IP/hub defaults must be known during plan')
check(not re.search(r'\bcommand\s*=\s*apply\b',mock),'Terraform tests remain plan-only')
check('/publicIPAddresses/mock-public-ip' in mock,'known mock public-IP ID must be ARM-type-valid')
key=re.search(r'ssh_public_key\s*=\s*"([^"]+)"',mock)[1].split()
wire=base64.b64decode(key[1],validate=True)
algorithm=b'ssh-ed25519';public=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
check(key[0]=='ssh-ed25519' and wire==struct.pack('>I',len(algorithm))+algorithm+struct.pack('>I',len(public))+public,'well-formed published RFC8032 PUBLIC test vector')
check('RFC8032-TEST-ONLY-NEVER-DEPLOY' in mock,'test-key deployment warning')
has('main.tf','count = var.deploy_lab ? 1 : 0','vendor_profile = var.vendor_profile')
for name in ['deploy_lab','image_prerequisites_confirmed','vendor_ready','enable_internet_intent','fixtures_ready','internet_routes_verified','vendor_deny_policy_verified','test_paths_enabled']:
 s=(R/'variables.tf').read_text().split('variable "'+name+'" {',1)[1].split('\n}',1)[0];check('default=false' in compact_hcl(s),'closed gate '+name)
has('variables.tf','Microsoft.Network/networkVirtualAppliances','Microsoft.Solutions/applications','integration_kind','["security", "dual_role"]','virtualHubs/partner-hub','var.vendor_deny_policy_verified','length(var.egress_public_ips) > 0','192.0.2.0/24','100.64.0.0/10','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','240.0.0.0/4','lower(var.subscription_id)','versions/[0-9]+')
s=(R/'module/main.tf').read_text();alltf='\n'.join(p.read_text() for p in R.rglob('*.tf'))
for token in ['name = "partner-hub"','address_prefix = "10.0.0.0/23"','type = "Standard"','name = "connect-app"','internet_security_enabled = true','count = var.enable_internet_intent ? 1 : 0','name = "InternetTrafficPolicy"','destinations = ["Internet"]','next_hop = var.vendor_profile.nva_resource_id','name = "internet-inspection"','test_nsg_action = var.test_paths_enabled ? "Allow" : "Deny"','name = "origin-public-ip"','!contains(var.egress_public_ips, self.ip_address)','"test-egress" : "test-origin-ingress"','destination_port_ranges = ["8080", "8081"]','"${azurerm_public_ip.origin.ip_address}/32"','"${local.origin_ip}/32"','length(var.egress_public_ips) == 0 ? "*" : null','[for ip in sort(tolist(var.egress_public_ips)) : "${ip}/32"]','public_ip_address_id = each.key == "origin" ? azurerm_public_ip.origin.id : null','default_outbound_access_enabled = false','ip_forwarding_enabled = false']:
 check(compact_hcl(token) in compact_hcl(s),'topology/NSG '+token)
check(s.count('resource "azurerm_virtual_network_peering"')==2,'only management/app peerings')
check(compact_hcl(s).count('allow_gateway_transit=false')==2 and compact_hcl(s).count('use_remote_gateways=false')==2 and compact_hcl(s).count('allow_forwarded_traffic=false')==2,'no default sharing/forwarded transit in management peering')
check('bastion="10.40.2.0/26"' in compact_hcl(s) and 'address_space=["10.40.0.0/16"]' in compact_hcl(s),'Bastion isolated from learned default')
check('azurerm_virtual_network.management' not in re.search(r'resource "azurerm_virtual_hub_connection".*?\n}',s,re.S)[0],'management never hub-connected')
check(s.count('resource "azurerm_virtual_hub_connection"')==1,'only app attached to hub');check(not re.search(r'\brouting\s*{',s),'no competing routing ownership');check('destinations=["PrivateTraffic"]' not in compact_hcl(s),'Internet-only')
for forbidden in ['resource "azurerm_route_table"','resource "azurerm_nat_gateway"','resource "azurerm_lb"','resource "azurerm_firewall"','resource "azurerm_network_virtual_appliance"','resource "azurerm_managed_application"','tls_private_key','data "azapi_resource"','cloudInitConfiguration','AZFWNetworkRule']:
 check(forbidden not in alltf,'no fake ownership/substitute '+forbidden)
has('module/compute.tf','source_image_id = var.image_id','disable_password_authentication = true','package_update = false','package_upgrade = false','egress_public_ips = []','origin_public_ip = azurerm_public_ip.origin.ip_address','each.key == "origin" ? ["systemctl", "enable", "--now"','azure-partner-fixture@8080.service','azure-partner-fixture@8081.service','/etc/azure-partner-lab.json')
check('var.egress_public_ips' not in (R/'module/compute.tf').read_text(),'E pool changes cannot replace custom_data VMs');check('8082' not in (R/'module/compute.tf').read_text(),'no app reverse listener')
has('module/management.tf','for_each = local.spokes','sku                    = "Standard"','tunneling_enabled      = true','GatewayManager','AzureLoadBalancer')
has('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','--subscription "$SUBSCRIPTION_ID"','Unexpected external profile ID','NVA output/profile mismatch','read_optional_output()','Unexpected scoped VM ID','Unexpected NIC ID map','Unexpected scoped NIC ID')
has('scripts/collect-control-plane.sh','--resource-type RouteTable','--api-version 2025-05-01 --query','nva-projected','managed-app-projected','vendor-identity-comparison','vendor-runtime-evidence-REQUIRED.txt','NOT_PERFORMED','read_optional_output nva_resource_id','read_optional_output routing_intent_id','mkdir -- "$OUT"','completed_utc','shell_exit','PRIVATE-HANDLING-REQUIRED.txt','client-side','without redaction')
collector=(R/'scripts/collect-control-plane.sh').read_text();check('AZFWNetworkRule' not in collector,'no generic vendor KQL');check('get-effective-routes' in collector and '--resource-type NVA' not in collector,'Internet-only default route view')
for line in collector.splitlines():
 if line.lstrip().startswith('collect ') and ('--ids "$NVA_ID"' in line or '--ids "$APP_ID"' in line):
  check('--query' in line,'secret-prone reads must project');check(not any(x in line for x in ['cloudInitConfiguration','bootStrapConfigurationBlobs','parameters:','outputs:']),'projection secret exclusions')
has('scripts/make-runtime-config.sh','os.O_EXCL','0o600','a.is_global','a.is_multicast','x==d','len(set(pool))','uploads nothing')
has('guest/probe.py','attempted_local','attempted_destination','completed_utc','expected_source_preserved','NEEDS_REVIEW','PARTNER_LAB_CONFIG','runtime-config.json')
files=['guest/probe.py','fixtures/server.py','scripts/partner-ready','scripts/partner-probe','fixtures/azure-partner-fixture@.service'];estimate=sum(4*((len((R/p).read_bytes())+2)//3) for p in files)+8192
check(estimate<65535,'conservative custom-data estimate');print(f'Base64 source payload +8KiB metadata reserve: {estimate} bytes; NOT Terraform-rendered custom_data.')
has('README.md','not self-contained','vendor_deny_policy_verified','Default','NOT RUN','NEEDS_REVIEW','source A','E:q','0/0 -> None','managed application','stateful')
print(f'PASS {count} source assertions including text/brace counts. No HCL/provider/vendor/cloud validation implied.')
