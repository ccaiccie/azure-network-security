#!/usr/bin/env python3
"""Source-text/AST invariants only; deliberately NOT an HCL/provider parser."""
import ast,re
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def check(ok,msg):
 global count
 count+=1
 assert ok,msg
def has(name,*tokens):
 text=(R/name).read_text()
 for token in tokens:check(token in text,f'{name} missing {token}')
for p in R.rglob('*.py'):ast.parse(p.read_text());check(True,'AST '+str(p))
for p in list(R.rglob('*.tf'))+list(R.rglob('*.tftest.hcl')):
 text=p.read_text();check(not re.search(r'=\s+=',text),'corrupt equality '+str(p))
 # Only bracket balance after strings/comments removed. This does NOT validate HCL.
 stripped=re.sub(r'"(?:\\.|[^"\\])*"|#[^\n]*|//[^\n]*|/\*.*?\*/','',text,flags=re.S)
 stack=[]
 for c in stripped:
  if c in '{[(':stack.append(c)
  elif c in '}])':
   check(bool(stack) and stack.pop() == {'}':'{',']':'[',')':'('}[c],'source bracket mismatch '+str(p))
 check(not stack,'unclosed source bracket '+str(p))
has('versions.tf','= 5.12.0','>= 1.9.0','resource_provider_registrations = "none"','prevent_deletion_if_contains_resources = true')
has('main.tf','count = var.deploy_lab ? 1 : 0','test_paths_enabled = var.test_paths_enabled')
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module validation parity')
for gate in ['deploy_lab','image_prerequisites_confirmed','fixtures_ready','private_routes_verified','test_paths_enabled','allow_test_flow']:
 text=(R/'variables.tf').read_text();chunk=text.split('variable "'+gate+'" {',1)[1].split('\n}',1)[0];check('default = false' in chunk,'closed gate '+gate)
has('variables.tf','lower(var.subscription_id)','versions/[0-9]+','var.deploy_lab && var.test_paths_enabled && var.fixtures_ready && var.private_routes_verified','var.deploy_lab && var.fixtures_ready && var.private_routes_verified')
has('module/main.tf','name = "lab-wan"','type = "Standard"','name = "secured-hub"','address_prefix = "10.0.0.0/23"','virtual_router_auto_scale_min_capacity = 2','bgp_route_propagation_enabled = true','name = "block-internet"','address_prefix = "0.0.0.0/0"','next_hop_type = "None"','destinations = ["PrivateTraffic"]','next_hop = azurerm_firewall.lab.id','name = "private-inspection"','name = "PrivateTrafficPolicy"','test_nsg_action = var.test_paths_enabled ? "Allow" : "Deny"','test_firewall_action = var.allow_test_flow ? "Allow" : "Deny"')
main=(R/'module/main.tf').read_text();alltf='\n'.join(p.read_text() for p in R.rglob('*.tf'))
check(main.count('internet_security_enabled = false')==2,'both connection internet gates closed')
check(main.count('resource "azurerm_virtual_hub_connection"')==2,'two hub connections')
check(not re.search(r'\brouting\s*{',main),'no connection routing ownership conflict')
for bad in ['resource "azurerm_virtual_network_peering"','resource "azurerm_virtual_hub_route_table"','next_hop_in_ip_address','tls_private_key','resource "azurerm_nat_gateway"','resource "azurerm_lb"','AzureFirewallSubnet']:
 check(bad not in alltf,'forbidden topology '+bad)
for word in ['"10.10.1.10/32"','"10.20.1.20/32"','ports = ["8080", "8081"]','ports = ["8082"]','priority = 100','priority = 101','priority = 110','priority = 200','priority = 4000','destination_address_prefix = "AzurePlatformDNS"','ip_forwarding_enabled = false','default_outbound_access_enabled = false']:
 check(word in main,'exact NSG/topology '+word)
check(alltf.count('resource "azurerm_public_ip"')==1,'public IP resource only for_each Bastion, F managed')
has('module/firewall.tf','name = "private-policy"','sku_name = "AZFW_Hub"','sku_tier = "Standard"','public_ip_count = 1','name = "private-rules"','priority = 200','name = "deny-healthy-alternate"','name = "deny-reverse-new"','name = "test-flow"','name = "deny-app-alt-8081"','name = "deny-backend-new-8082"','name = "app-to-backend-8080"','action = local.test_firewall_action','threat_intelligence_mode = "Alert"')
fw=(R/'module/firewall.tf').read_text();check(fw.count('network_rule_collection {')==3,'three network-only collections');check(fw.count('action = "Deny"')==2,'negative collections always denied')
for bad in ['application_rule_collection {','nat_rule_collection {','private_ip_ranges','base_policy_id']:
 check(bad not in fw,'no rule/policy/SNAT broadening '+bad)
has('module/management.tf','for_each = local.spokes','sku                    = "Standard"','tunneling_enabled      = true','shareable_link_enabled = false','GatewayManager','AzureLoadBalancer')
check('azurerm_subnet.bastion' not in re.search(r'resource "azurerm_subnet_route_table_association".*?\n}',main,re.S)[0],'no workload UDR on Bastion')
has('module/compute.tf','source_image_id = var.image_id','disable_password_authentication = true','package_update = false','package_upgrade = false','azure-vwan-fixture@8082.service','azure-vwan-fixture@8080.service','azure-vwan-fixture@8081.service','/etc/azure-vwan-lab.json','azurerm_virtual_hub_routing_intent.private','azurerm_monitor_diagnostic_setting.firewall')
has('module/diagnostics.tf','AZFWNetworkRule','AZFWThreatIntel','Dedicated','local_authentication_enabled = false')
has('module/outputs.tf','one(azurerm_firewall.lab.virtual_hub).private_ip_address','one(azurerm_firewall.lab.virtual_hub).public_ip_addresses','workspace_customer_id','hub_default_route_table_id','test_nsg_action')
has('guest/probe.py','attempted_local','attempted_destination','completed_utc','tcp_connect_completed','request_write_status','NEEDS_REVIEW','expected_source_preserved','auto_open = 0','exist_ok=False')
has('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','--subscription "$SUBSCRIPTION_ID"','Invalid resource ID or approved subscription mismatch')
has('scripts/collect-control-plane.sh','require_extensions virtual-wan azure-firewall','mkdir -- "$OUT"','completed_utc','shell_exit','show-effective-route-table','list-effective-nsg','--resource-type RouteTable','FIREWALL_ROUTE_RESOURCE_TYPE','NOT_PERFORMED','firewall-onward-routes-REQUIRED.txt','default-effective-routes','FAILED=$((FAILED+1))')
files=['guest/probe.py','fixtures/server.py','scripts/vwan-ready','scripts/vwan-probe','fixtures/azure-vwan-fixture@.service']
estimate=sum(4*((len((R/p).read_bytes())+2)//3) for p in files)+8192
check(estimate<65535,'cloud-init conservative source payload ceiling');print(f'Payload base64 lengths +8KiB metadata reserve={estimate} bytes; estimate, not Terraform rendered custom_data.')
has('README.md','primary_shared_key','secondary_shared_key','NOT RUN','test_paths_enabled=false','intent','stateful','no virtual hub router dataplane','NEEDS_REVIEW')
print(f'PASS {count} source assertions. Bracket/text/AST checks do not validate HCL/provider/Azure behavior.')
