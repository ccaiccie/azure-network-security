#!/usr/bin/env python3
"""Focused text regression checks only, NOT an HCL parser or provider validator."""
from pathlib import Path
import ipaddress
import re

ROOT=Path(__file__).resolve().parents[1]
MAIN=(ROOT/'main.tf').read_text()
VARIABLES=(ROOT/'variables.tf').read_text()
VERSIONS=(ROOT/'versions.tf').read_text()
MGMT=(ROOT/'management.tf').read_text()
DIAG=(ROOT/'diagnostics.tf').read_text()
HCL_FILES=list(ROOT.glob('*.tf'))+list(ROOT.glob('*.tfvars.example'))+list((ROOT/'tests').glob('*.tftest.hcl'))
ALL='\n'.join(p.read_text() for p in HCL_FILES)
def has(text,snippet):return re.sub(r'\s+','',snippet) in re.sub(r'\s+','',text)
checks={
 'intact comparison operators':not re.search(r'[=!<>][ \t]+=',ALL),
 'provider exact pin':has(VERSIONS,'version = "= 5.12.0"'),
 'registration disabled':has(VERSIONS,'resource_provider_registrations = "none"'),
 'computed firewall IP':has(MAIN,'firewall_ip = azurerm_firewall.lab.ip_configuration[0].private_ip_address'),
 'explicit private subnets':has(MAIN,'default_outbound_access_enabled = false'),
 'all four forwarded peering flags':len(re.findall(r'allow_forwarded_traffic\s*=\s*true',MAIN))==4,
 'four peering declarations only':len(re.findall(r'resource "azurerm_virtual_network_peering"',MAIN))==4,
 'all VirtualAppliance routes use computed F and None has no hop':has(MAIN,'next_hop_in_ip_address = route.value.type == "VirtualAppliance" ? local.firewall_ip : null'),
 'routes consume tested specifications':has(MAIN,'for_each = local.route_specs[each.key]') and has(MAIN,'address_prefix = route.value.prefix') and has(MAIN,'next_hop_type = route.value.type'),
 'NSGs consume tested specifications':has(MAIN,'for_each = local.test_nsg_rules[each.key]') and has(MAIN,'destination_port_ranges = security_rule.value.ports') and has(MAIN,'source_address_prefix = security_rule.value.source') and has(MAIN,'destination_address_prefix = security_rule.value.destination'),
 'same-VNet switch adds C through merge':has(MAIN,'workloads = merge(local.base_workloads, var.enable_same_vnet ? local.same_vnet_workload : {})'),
 'C shares existing app VNet':has(MAIN,'vnet_key = "app"') and has(MAIN,'subnet_name = "same-vnet"') and has(MAIN,'virtual_network_name = azurerm_virtual_network.workload[each.value.vnet_key].name'),
 'A-to-C /24 exact':has(MAIN,'{ name = "same-vnet-forward", prefix = "10.10.2.0/24", type = "VirtualAppliance" }'),
 'C-to-A /24 exact':has(MAIN,'{ name = "same-vnet-return", prefix = "10.10.1.0/24", type = "VirtualAppliance" }'),
 'C return route has separate bounded switch':has(MAIN,'role == "c" && var.same_vnet_return_route_enabled ? ['),
 'C policy explicit allow and both named denies':all(name in MAIN for name in ['allow-app-to-same-vnet','deny-same-vnet-reverse-new','deny-same-vnet-alternate-port']),
 'explicit remote route switch':has(MAIN,'role != "c" && var.explicit_remote_routes ? ['),
 'blackhole switch only on db':has(MAIN,'role == "db" && var.return_route_blackhole ? ['),
 'blackhole exact prefix and type':has(MAIN,'{ name = "experiment-return-blackhole", prefix = "10.10.1.10/32", type = "None" }'),
 'allow is named':has(MAIN,'name = "allow-app-to-test"'),
 'alternate deny is named':has(MAIN,'name = "deny-app-alternate-port"'),
 'reverse deny is named':has(MAIN,'name = "deny-reverse-new"'),
 'only one firewall Allow collection':len(re.findall(r'action\s*=\s*"Allow"',MAIN))==1,
 'no application collection':not re.search(r'(?m)^\s*application_rule_collection\s*{',MAIN),
 'no SNAT override':not re.search(r'(?m)^\s*private_ip_ranges\s*=',MAIN),
 'no NAT or DNAT resources':not re.search(r'resource\s+"azurerm_nat_gateway"|(?m:^\s*nat_rule_collection\s*{)',ALL),
 'workload NSG permits required negative ports':has(MAIN,'inbound_test_ports = ["8080", "8081"]') and has(MAIN,'outbound_test_ports = ["8080", "8081"]'),
 'workload NSG deny both directions':has(MAIN,'for_each = toset(["Inbound", "Outbound"])'),
 'no workload Internet or AzureCloud allow':'destination_address_prefix = "Internet"' not in MAIN and 'destination_address_prefix = "AzureCloud"' not in MAIN,
 'SSH password disabled':has(MAIN,'disable_password_authentication = true'),
 'no Terraform private key generation':'tls_private_key' not in ALL,
 'no provisioner':not re.search(r'\bprovisioner\s+"',ALL),
 'concrete image required':'latest is deliberately rejected' in VARIABLES,
 'fixture ports A and B':has(MAIN,'listen_ports = [8080]') and has(MAIN,'listen_ports = [8080, 8081]'),
 'fixture service startup is owned':'azure-ew-fixture@${port}.service' in MAIN,
 'cloud-init invokes readiness':'/var/log/azure-ew-readiness.log' in MAIN,
 'no package bootstrap downloads':has(MAIN,'package_update = false') and has(MAIN,'package_upgrade = false'),
 'Bastion Standard with native tunnel':has(MGMT,'sku = "Standard"') and has(MGMT,'tunneling_enabled = true'),
 'resource-specific logs':has(DIAG,'log_analytics_destination_type = "Dedicated"'),
 'curl config ignored': 'curl -q -4' in (ROOT/'scripts/guest-probe.sh').read_text(),
}
nic=MAIN.split('resource "azurerm_network_interface" "workload" {',1)[1].split('resource "azurerm_linux_virtual_machine"',1)[0]
checks['workload NIC has no public IP']='public_ip_address_id' not in nic
nets=[ipaddress.ip_network(x) for x in ['10.0.0.0/16','10.10.0.0/16','10.20.0.0/16']]
checks['VNet ranges nonoverlapping']=all(not a.overlaps(b) for i,a in enumerate(nets) for b in nets[i+1:])
for name,passed in checks.items():print(('PASS' if passed else 'FAIL')+': '+name)
if not all(checks.values()):raise SystemExit(1)
print(f'{len(checks)} focused source checks passed; NOT Terraform or runtime validation.')
