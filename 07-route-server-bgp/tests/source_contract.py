#!/usr/bin/env python3
"""Source text/AST checks, NOT HCL/FRR/nft/provider/kernel execution."""
import ast,re,gzip
from pathlib import Path
R=Path(__file__).resolve().parents[1];count=0
def check(ok,msg):
 global count
 count+=1
 assert ok,msg
def has(path,*tokens):
 s=(R/path).read_text()
 for t in tokens:check(t in s,f'{path} missing {t}')
for p in R.rglob('*.py'):ast.parse(p.read_text());check(True,'AST '+str(p))
for p in list(R.rglob('*.tf'))+list(R.rglob('*.tftest.hcl')):check(not re.search(r'=\s+=',p.read_text()),'corrupt equality '+str(p))
has('versions.tf','= 5.12.0','>= 1.9.0','resource_provider_registrations = "none"')
has('main.tf','count = var.deploy_lab ? 1 : 0','frr_version = var.frr_version')
has('variables.tf','default = false','var.image_prerequisites_confirmed','lower(var.subscription_id)','versions/[0-9]+','^10[.]4([.][0-9]+)?$')
check((R/'variables.tf').read_text()==(R/'module/variables.tf').read_text(),'same variable validation')
has('module/routeserver.tf','branch_to_branch_traffic_enabled = false','hub_routing_preference = "ASPath"','peer_asn = 65010','for_each = local.nvas','peer_ip = azurerm_network_interface.vm[each.key].private_ip_address','length(self.virtual_router_ips) == 2','self.virtual_router_asn != 65010')
has('module/main.tf','rs_cidr = "10.0.1.0/26"','destination_prefix = "172.20.50.0/24"','destination_ip = "172.20.50.10"','remote_ip = "10.30.1.20"','nva1 = "10.0.2.4", nva2 = "10.0.2.5"','rs_peer_ips = sort(tolist(azurerm_route_server.lab.virtual_router_ips))','rs_asn = azurerm_route_server.lab.virtual_router_asn','propagation = true','propagation = false','bgp_route_propagation_enabled = each.value.propagation','name = "nva-substrate"','bgp_route_propagation_enabled = false','use_remote_gateways = true','allow_gateway_transit = true','ip_forwarding_enabled = contains(keys(local.nvas), each.key)','source_address_prefixes = security_rule.value == "Inbound"','destination_address_prefixes = security_rule.value == "Outbound"','priority = 120','priority = 110','priority = 200','priority = 4000','default_outbound_access_enabled = false')
main=(R/'module/main.tf').read_text();alltf='\n'.join(p.read_text() for p in R.rglob('*.tf'))
check(main.count('resource "azurerm_virtual_network_peering"')==4,'four directional peerings');check(main.count('use_remote_gateways = true')==1,'only app uses remote');check(main.count('allow_gateway_transit = true')==1,'only hub to app gateway transit')
check('next_hop_in_ip_address' not in main,'no recursive/exact-prefix UDR');check('"VirtualNetworkGateway"' not in main,'no unsupported VNG UDR');check(alltf.count('resource "azurerm_public_ip"')==2,'only RS management and Bastion PIPs');check('azurerm_lb' not in alltf and 'azurerm_firewall' not in alltf and 'azurerm_nat_gateway' not in alltf,'no ILB/firewall/NAT gateway');check('tls_private_key' not in alltf,'no generated secret key')
# Extract association blocks, avoiding comments and subnet definition false positives.
for m in re.finditer(r'resource "azurerm_subnet_(?:network_security_group|route_table)_association"[^}]+}',alltf,re.S):check('azurerm_subnet.routeserver' not in m.group(0),'no NSG/UDR on RS subnet')
has('module/compute.tf','source_image_id = var.image_id','package_update = false','package_upgrade = false','rs_peer_ips = local.rs_peer_ips','rs_asn = local.rs_asn','frr_version = var.frr_version','each.key == "app" ? [','rs-boot.service','frr.service.d/rs-lab.conf','remote-ready','rs-evidence','azurerm_route_server_bgp_connection.nva')
for token in ['bgp no-rib','bgp network import-check','neighbor {p} ebgp-multihop 255','neighbor {p} timers 60 180','maximum-prefix 20 force','maximum-prefix-out 1','soft-reconfiguration inbound','set as-path prepend 65010 65010','RS-EXPORT-CLOSED','RS-EXPORT-OPEN','ip prefix-list RS-IN-DENY seq 10 deny 0.0.0.0/0 le 32','frr_base_check','scoped-overlay-snat','ct state new tcp flags & (fin | syn | rst | ack) == syn','allow-reverse-snat-reply','deny-alternate-8081','tcp option maxseg size set 1360',"'mtu','1400'","'proto','186'",'signal.SIGHUP,signal.SIGINT,signal.SIGTERM',"['nft','-c','-f',path]","['nft','-f',path]",'recovery.json','events.jsonl','LOCK_EX|fcntl.LOCK_NB','live=True','recovery_safety_errors']:
 has('guest/controller.py',token)
controller=(R/'guest/controller.py').read_text();check('flush ruleset' not in controller and 'conntrack -F' not in controller,'no global flush');check('no_zebra' not in controller,'zebra not disabled');has('guest/frr-daemons','zebra=yes','bgpd=yes','vtysh_enable=yes');has('guest/frr-lab.conf','Requires=rs-boot.service','After=rs-boot.service')
has('guest/probe.py','attempted_local','attempted_destination','tcp_connect_completed','completed_utc','expected-node','observed_fixture_peer_tuples','exist_ok=False')
has('scripts/common.sh','AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no','route_server_id','--subscription "$SUBSCRIPTION_ID"')
has('scripts/collect-control-plane.sh','mkdir -- "$OUT"','completed_utc','shell_exit','list-learned-routes','list-advertised-routes','show-effective-route-table','list-effective-nsg','metric-definitions.json')
has('scripts/rs-evidence','mkdir -- "$OUT"','record()','show bgp ipv4 unicast summary json','advertised-routes json','traffic.pcap','ip proto 47','tcp port 179','.exit','completed_utc')
has('module/compute.tf','encoding = "gz+b64", content = base64gzip(file("${path.module}/../guest/controller.py"))')
has('guest/controller.py','transition.json','@contextlib.contextmanager','last_recorded_intent','verify_withdrawn','totalPrefixCounter','advertisedRoutes','Two-peer export policy change not observed locally','deny-other-decapsulated-input','local-tunnel-readiness-reply')
# Controller uses standard cloud-init gz+b64; conservative encoded source-payload ceiling: bytes base64 expanded plus 8KiB metadata reserve.
role_files={'app':['guest/probe.py','scripts/rs-probe'],'nva':['guest/controller.py','scripts/rs-control','scripts/rs-evidence','guest/rs-boot.service','guest/frr-daemons','guest/frr-lab.conf'],'remote':['guest/controller.py','scripts/rs-control','scripts/rs-evidence','guest/rs-boot.service','fixtures/server.py','scripts/remote-ready','fixtures/azure-routeserver-fixture@.service']}
for role,files in role_files.items():
 estimate=sum(4*((len(gzip.compress((R/p).read_bytes(),mtime=0) if p=="guest/controller.py" else (R/p).read_bytes())+2)//3) for p in files)+8192
 check(estimate<65535,f'{role} conservative custom-data estimate too large: {estimate}')
 print(f'{role} source payload +8KiB metadata reserve: {estimate} bytes (estimate, not Terraform-rendered custom_data).')
print(f'PASS {count} source assertions. No HCL/provider/FRR/nft/kernel/Azure validation implied.')
