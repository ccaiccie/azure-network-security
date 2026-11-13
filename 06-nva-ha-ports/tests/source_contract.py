#!/usr/bin/env python3
"""Text/AST source assertions, NOT HCL/provider/nft/kernel validation."""
import ast,re
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def norm(t,path=''):
 return re.sub(r'[ \t]+=[ \t]+',' = ',t) if path.endswith(('.tf','.hcl')) else t  # terraform fmt aligns '='
texts={str(p.relative_to(R)):norm(p.read_text(),str(p)) for p in R.rglob('*') if p.is_file() and p.suffix in ('.tf','.py','.sh','.service','.hcl') and not any(x in p.parts for x in ('validation','__pycache__','.terraform'))}
def check(condition,message):
 global count
 count+=1
 assert condition,message
def contains(path,*needles):
 for n in needles:check(norm(n,path) in norm((R/path).read_text(),path),f'{path} missing {n}')
for path,text in texts.items():
 if path.endswith('.py'):ast.parse(text);check(True,'AST '+path)
 if path.endswith(('.tf','.hcl')):check(not re.search(r'=\s+=',text),'corrupted equality '+path)
contains('versions.tf','= 5.12.0','>= 1.9.0','subscription_id','resource_provider_registrations = "none"')
contains('main.tf','count = var.deploy_lab ? 1 : 0','source = "./module"')
contains('variables.tf','default = false','var.image_prerequisites_confirmed','var.nva_zones == null','length(toset(var.nva_zones)) == 2','lower(var.subscription_id)','versions/[0-9]+','No default;','Never supply a private key')
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'root/module input validation parity')
contains('module/main.tf','nva1 = "10.0.2.4", nva2 = "10.0.2.5"','frontend_ip = "10.0.2.10"','app_ip = "10.10.1.10"','backend_ip = "10.20.1.20"','remote = "10.20.0.0/16"','remote = "10.10.0.0/16"','next_hop_in_ip_address = local.frontend_ip','name = "nva-block-internet"','ip_forwarding_enabled = contains(keys(local.nvas), each.key)','source_address_prefix = "AzureLoadBalancer"','destination_address_prefix = "AzurePlatformDNS"','priority = 4000','priority = 120','priority = 110','priority = 200','default_outbound_access_enabled = false','source_ports = ["8080", "8081"]','destination_ports = ["8080", "8081"]','source_port_range = length(','destination_port_range = length(')
main=norm((R/'module/main.tf').read_text(),'x.tf');check(main.count('resource "azurerm_virtual_network_peering"')==4,'four directional peerings');check(main.count('allow_forwarded_traffic = true')==4,'forwarded on every peering');check(main.count('allow_gateway_transit = false')==4,'no gateway transit')
nva_route=main.split('resource "azurerm_route_table" "nva"')[1].split('resource ')[0];check(nva_route.count('route {')==1 and 'next_hop_type = "None"' in nva_route,'NVA route no recursive F')
lb=norm((R/'module/load-balancer.tf').read_text(),'x.tf');check(lb.count('resource "azurerm_lb"')==1 and lb.count('resource "azurerm_lb_backend_address_pool"')==1 and lb.count('resource "azurerm_lb_rule"')==1,'one LB/pool/rule');contains('module/load-balancer.tf','protocol = "All"','frontend_port = 0','backend_port = 0','floating_ip_enabled = true','load_distribution = "Default"','disable_outbound_snat = true','tcp_reset_enabled = false','for_each = local.nvas','no_healthy_backends_behavior = "AllProbedDown"','probe_threshold = 2','number_of_probes = 2','interval_in_seconds = 5','port = 8008','request_path = "/healthz"','zones = var.nva_zones == null ? null : ["1", "2", "3"]')
contains('module/compute.tf','source_image_id = var.image_id','disable_password_authentication = true','package_update = false','package_upgrade = false','backend-ready','nva-evidence','nva-control','nva-probe','nva-boot.service','nva-health-monitor.service','nva-health.service','azure-nva-fixture@8081.service')
alltf='\n'.join(t for p,t in texts.items() if p.endswith('.tf'));check('azurerm_firewall' not in alltf and 'azurerm_nat_gateway' not in alltf,'no managed firewall/NAT gateway');check('private_key' not in alltf and 'tls_private_key' not in alltf,'no private key');check(alltf.count('resource "azurerm_public_ip"')==1,'Bastion only public IP');contains('module/management.tf','sku                    = "Standard"','tunneling_enabled      = true','AzureBastionSubnet')
contains('guest/controller.py','signal.SIGHUP,signal.SIGINT,signal.SIGTERM','ct state new tcp flags & (fin | syn | rst | ack) == syn','ct state established','deny-alternate-8081',"['nft','-c','-f',path]","['nft','-f',path]",'failure-recovery.json','original-sysctl.json','events.jsonl','os.fsync','except BrokenPipeError','Unresolved recovery record exists','tcp_loose','time.sleep(2)','<=6','local-only-not-end-to-end-or-Azure-eligibility')
contains('guest/probe.py','attempted_local','attempted_destination','tcp_connect_completed','request_write_status','completed_utc','started_utc','stream_end','signal.setitimer','mkdir','exist_ok=False')
contains('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','STATE_SUB','--subscription "$SUBSCRIPTION_ID"')
contains('scripts/collect-control-plane.sh','mkdir -- "$OUT"','completed_utc','shell_exit','show-effective-route-table','list-effective-nsg','DipAvailability','VipAvailability')
contains('scripts/nva-evidence','mkdir -- "$OUT"','completed_utc','conntrack','--orig-src','timeout','tcpdump','capture-seconds')
check('flush ruleset' not in (R/'guest/controller.py').read_text().replace('never flush ruleset',''),'no global nft flush')
print(f'PASS {count} source assertions. Text/AST checks do not validate HCL/provider schema/nft syntax or runtime.')
