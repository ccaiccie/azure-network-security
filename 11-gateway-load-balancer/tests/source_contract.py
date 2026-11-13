#!/usr/bin/env python3
"""Offline source/text invariants; NOT a genuine HCL/provider/nft/kernel validation."""
import ast,base64,gzip,re
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def check(ok,msg):
 global count
 count+=1
 assert ok,msg
def has(name,*tokens):
 s=(R/name).read_text()
 for t in tokens:check(t in s,f'{name} missing {t}')
for p in R.rglob('*.py'):ast.parse(p.read_text());check(True,'AST '+str(p))
for p in list(R.rglob('*.tf'))+list(R.rglob('*.tftest.hcl')):
 s=p.read_text();check(not re.search(r'=\s+=',s),'corrupt equality '+str(p));check(s.count('{')==s.count('}'),'brace counts '+str(p))
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module validation parity')
has('versions.tf','= 5.12.0','>= 1.9.0','resource_provider_registrations = "none"','prevent_deletion_if_contains_resources = true')
has('main.tf','count = var.deploy_lab ? 1 : 0','client_public_ip = var.client_public_ip')
for name in ['deploy_lab','image_prerequisites_confirmed','appliances_ready','application_ready','enable_chain','test_paths_enabled']:
 s=(R/'variables.tf').read_text().split('variable "'+name+'" {',1)[1].split('\n}',1)[0];check('default = false' in s,'closed gate '+name)
has('variables.tf','var.appliances_ready && var.application_ready','!var.test_paths_enabled','var.enable_chain','198.51.100.0/24','203.0.113.0/24','100.64.0.0/10','224.0.0.0/4','240.0.0.0/4','versions/[0-9]+','lower(var.subscription_id)')
has('module/main.tf','nva1 = { ip = "10.0.1.4"','nva2 = { ip = "10.0.1.5"','app = { ip = "10.20.1.20"','gwlb_ip = "10.0.2.10"','management_prefix = "10.40.2.0/26"','provider = "10.0.0.0/16"','consumer = "10.20.0.0/16"','management = "10.40.0.0/16"','default_outbound_access_enabled = false','ip_forwarding_enabled = each.key != "app"')
s=(R/'module/main.tf').read_text();check(s.count('resource "azurerm_virtual_network_peering"')==2,'two management peering resource sets');check(s.count('allow_forwarded_traffic = false')==2 and s.count('allow_gateway_transit = false')==2 and s.count('use_remote_gateways = false')==2,'no peering transit')
alltf='\n'.join(p.read_text() for p in R.rglob('*.tf'))
for forbidden in ['resource "azurerm_route_table"','resource "azurerm_route"','resource "azurerm_nat_gateway"','resource "azurerm_lb_outbound_rule"','resource "azurerm_firewall"','resource "tls_private_key"','resource "azurerm_virtual_hub"']:
 check(forbidden not in alltf,'no substitute/bypass '+forbidden)
has('module/lb.tf','sku = "Gateway"','sku_tier = "Regional"','name = "inspection-frontend"','name = "nva-pool"','identifier = 800','identifier = 801','type = "Internal"','type = "External"','protocol = "VXLAN"','port = 10800','port = 10801','for_each = toset(["nva1","nva2"])','name = "ha-ports"','frontend_port = 0','backend_port = 0','floating_ip_enabled = false','disable_outbound_snat = true','name = "public-lb"','name = "public-frontend"','gateway_load_balancer_frontend_ip_configuration_id = var.enable_chain ?','name = "app-pool"','for_each = toset(["8080","8081"])','port = 8008','port = 8009','request_path = "/health"','self.ip_address != var.client_public_ip')
s=(R/'module/lb.tf').read_text();check(s.count('floating_ip_enabled = false')==2 and 'floating_ip_enabled = true' not in s,'both rule types nonfloating');check(s.count('disable_outbound_snat = true')==2,'both inbound-only');check(s.count('no_healthy_backends_behavior = "AllProbedDown"')==2,'explicit unvalidated all-unhealthy setting')
has('module/nsg.tf','name = "test-client-ingress"','priority = 100','access = local.test_nsg_action','source_address_prefix = "${var.client_public_ip}/32"','destination_port_ranges = ["8080","8081"]','name = "management-ssh"','priority = 110','name = "platform-readiness"','priority = 120','source_address_prefix = "AzureLoadBalancer"','priority = 130','protocol = "Udp"','destination_port_ranges = ["10800","10801"]','"10.0.0.0/16"','priority = 200','destination_address_prefix = "AzurePlatformDNS"','priority = 4000')
has('module/management.tf','name                   = "management-bastion"','sku                    = "Standard"','tunneling_enabled      = true','GatewayManager','AzureLoadBalancer','azurerm_virtual_network.lab["management"].name')
has('module/compute.tf','source_image_id = var.image_id','disable_password_authentication = true','encoding = "gz+b64"','base64gzip(file(','package_update = false','package_upgrade = false','underlay_mtu = 1550','inner_mtu = 1500','gwlb-prepare.service','gwlb-monitor.service','gwlb-health.service','azure-gwlb-fixture@8080.service','azure-gwlb-fixture@8081.service','azure-gwlb-app-health.service','/etc/azure-gwlb-app.json','/etc/azure-gwlb-lab.json')
has('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','--subscription "$SUBSCRIPTION_ID"','Unexpected scoped ID','Unexpected ID map','Unexpected map target','Unexpected probe IDs')
has('scripts/collect-control-plane.sh','PRIVATE-HANDLING-REQUIRED.txt','client-side','not automatically redacted','show-effective-route-table','list-effective-nsg','metrics list-definitions','runtime-evidence-REQUIRED.txt','NOT_PERFORMED','mkdir -- "$OUT"','completed_utc','shell_exit')
has('scripts/make-client-config.sh','os.O_EXCL','0o600','client_public_ip','consumer_public_ip','backend_ip','no upload or network probe')
has('guest/controller.py','table bridge {TABLE}','hook forward priority -200','deny-primary-8080-forward','deny-primary-8080-reverse','deny-alternate-8081-forward','allow-primary-8080-forward-capture-required','--acknowledge-capture-required','--confirm-guest-change','--acknowledge-sensitive-capture','gwlb-br0','gwlb-ext','gwlb-int','pending.json','SIG HUP'.replace(' ',''),'nolearning','server_bind')
has('guest/probe.py','attempted_local','completed_utc','NEEDS_REVIEW')
has('README.md','not a tested deployment','stateless','capture-required','no automatic expiry','client-side','NOT RUN','no inspection UDR','bridge-family','persistent','reconcile','provider10.0/16')
for role,files in {'nva':['guest/controller.py','scripts/gwlb-control','scripts/gwlb-evidence','guest/gwlb-prepare.service','guest/gwlb-monitor.service','guest/gwlb-health.service'],'app':['fixtures/server.py','scripts/gwlb-app-ready','fixtures/azure-gwlb-fixture@.service','fixtures/azure-gwlb-app-health.service']}.items():
 encoded=0
 for name in files:
  raw=(R/name).read_bytes();compressed=gzip.compress(raw,mtime=0);check(gzip.decompress(compressed)==raw,'gzip roundtrip '+name);encoded+=len(base64.b64encode(compressed))
 estimate=encoded+8192;check(estimate<65535,'conservative cloud-init source estimate '+role);print(f'{role}: gzip/base64 source payload+8KiB reserve={estimate} bytes, NOT Terraform-rendered custom_data.')
print(f'PASS {count} source assertions including text/brace counts. No HCL/provider/nft/kernel/cloud validation implied.')
