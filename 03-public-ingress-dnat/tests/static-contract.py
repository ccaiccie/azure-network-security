#!/usr/bin/env python3
"""Focused text guards, not an HCL parser, provider schema or Azure validation."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
MAIN=(ROOT/'main.tf').read_text(); VARS=(ROOT/'variables.tf').read_text()
MGMT=(ROOT/'management.tf').read_text(); DIAG=(ROOT/'diagnostics.tf').read_text()
VER=(ROOT/'versions.tf').read_text(); PROBE=(ROOT/'scripts/client-probe.sh').read_text()
ALL='\n'.join(p.read_text() for p in [*ROOT.glob('*.tf'),*ROOT.glob('*.tfvars.example'),*(ROOT/'tests').glob('*.tftest.hcl')])
def has(text,s): return re.sub(r'\s+','',s) in re.sub(r'\s+','',text)
checks={
 'intact comparison operators':not re.search(r'[=!<>][ \t]+=',ALL),
 'exact provider pin':has(VER,'version = "= 5.12.0"'),
 'no automatic provider registration':has(VER,'resource_provider_registrations = "none"'),
 'publication explicitly gated':has(MAIN,'count = var.publish_dnat ? 1 : 0'),
 'publication default off':has(VARS.split('variable "publish_dnat"',1)[1].split('variable ',1)[0],'default = false'),
 'public client required and single host':has(VARS,'endswith(var.allowed_client_cidr, "/32")') and 'default' not in VARS.split('variable "allowed_client_cidr"',1)[1].split('variable ',1)[0],
 'client CIDR validity':has(VARS,'can(cidrnetmask(var.allowed_client_cidr))'),
 'client canonical form':has(VARS,'var.allowed_client_cidr == "${cidrhost(var.allowed_client_cidr, 0)}/32"'),
 'documentation sources rejected':'198\\\\.51\\\\.100' in VARS and '203\\\\.0\\\\.113' in VARS,
 'DNAT actual computed P':has(MAIN,'destination_address = azurerm_public_ip.firewall.ip_address'),
 'DNAT actual source variable':has(MAIN,'source_addresses = [var.allowed_client_cidr]'),
 'DNAT exact public port':has(MAIN,'destination_ports = ["8443"]'),
 'DNAT exact backend port':has(MAIN,'translated_port = "8080"'),
 'DNAT backend destination':has(MAIN,'translated_address = local.backend_ip'),
 'group and collection identity':has(MAIN,'name = "test-rules"') and has(MAIN,'name = "publish-test"') and has(MAIN,'name = "operator-only"'),
 'no other firewall collections':not re.search(r'(?m)^\s*(?:network|application)_rule_collection\s*{',MAIN),
 'no custom SNAT policy':not re.search(r'(?m)^\s*private_ip_ranges\s*=',MAIN),
 'no management NIC forced tunnel':'management_ip_configuration' not in MAIN,
 'only two peering objects':len(re.findall(r'resource "azurerm_virtual_network_peering"',MAIN))==2,
 'forwarded traffic explicit':len(re.findall(r'allow_forwarded_traffic\s*=\s*true',MAIN))==2,
 'backend private subnet':has(MAIN,'default_outbound_access_enabled = false'),
 'backend single fixed IP':has(MAIN,'backend_ip = "10.20.1.10"'),
 'computed frontend F':has(MAIN,'firewall_ip = azurerm_firewall.lab.ip_configuration[0].private_ip_address'),
 'standalone route resources consume tested specs':has(MAIN,'for_each = local.route_specs') and has(MAIN,'address_prefix = each.value.prefix'),
 'no inline route configuration':not re.search(r'(?m)^\s*(?:dynamic "route"|route\s*[={])',MAIN),
 'None route has no IP':has(MAIN,'next_hop_in_ip_address = each.value.type == "VirtualAppliance" ? local.firewall_ip : null'),
 'blackhole entire firewall subnet':has(MAIN,'experiment-return-blackhole = { prefix = "10.0.1.0/26", type = "None" }'),
 'NSG consumes tested specs':has(MAIN,'for_each = local.backend_nsg_rules') and has(MAIN,'source_address_prefix = security_rule.value.source') and has(MAIN,'destination_port_range = security_rule.value.port'),
 'NSG translated source is firewall subnet':has(MAIN,'source = local.firewall_cidr, destination = "${local.backend_ip}/32", port = "8080"'),
 'no outbound NSG allow':not re.search(r'direction\s*=\s*"Outbound",\s*access\s*=\s*"Allow"',MAIN),
 'private SSH only':has(MAIN,'source = local.bastion_cidr, destination = "${local.backend_ip}/32", port = "22"'),
 'SSH passwords disabled':has(MAIN,'disable_password_authentication = true'),
 'no generated private key':'tls_private_key' not in ALL,
 'no provisioners':not re.search(r'\bprovisioner\s+"',ALL),
 'no package downloads':has(MAIN,'package_update = false') and has(MAIN,'package_upgrade = false'),
 'owned service startup':'["systemctl", "enable", "--now", "azure-dnat-fixture.service"]' in MAIN,
 'owned readiness captured':'/var/log/azure-dnat-readiness.log' in MAIN,
 'concrete image required':'latest is deliberately rejected' in VARS,
 'Bastion separate native path':has(MGMT,'name = "dnat-bastion"') and has(MGMT,'tunneling_enabled = true'),
 'Dedicated NAT logs':has(DIAG,'log_analytics_destination_type = "Dedicated"') and '"AZFWNatRule"' in DIAG,
 'curl ignores user config':'curl -q -4 --http1.1' in PROBE,
 'curl plain HTTP literal P':'"http://$P:$PORT/$CASE_ID"' in PROBE,
 'curl no redirects or insecure bypass':'--location' not in PROBE and '--insecure' not in PROBE,
 'probe checks translated peer subnet':"IPv4Network('10.0.1.0/26')" in PROBE,
 'declared source not asserted verified':'NOT independently verified' in PROBE,
 'negative results remain review':'RESULT=NEEDS_REVIEW' in PROBE,
}
nic=MAIN.split('resource "azurerm_network_interface" "backend"',1)[1].split('resource "azurerm_linux_virtual_machine"',1)[0]
checks['backend NIC no public IP']='public_ip_address_id' not in nic
custom=MAIN.split('custom_data =',1)[1]
checks['experiment flags do not change custom data']=not any('var.'+v in custom for v in ('publish_dnat','enable_default_route','return_route_blackhole'))
for name,passed in checks.items(): print(('PASS' if passed else 'FAIL')+': '+name)
if not all(checks.values()): raise SystemExit(1)
print(f'{len(checks)} source-contract checks passed; NOT HCL/provider/runtime validation.')
