#!/usr/bin/env python3
"""Small source-level regression checks, NOT an HCL parser or Terraform validate."""
from pathlib import Path
import ipaddress
import re

ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.tf").read_text()
MGMT = (ROOT / "management.tf").read_text()
VERSIONS = (ROOT / "versions.tf").read_text()
DIAG = (ROOT / "diagnostics.tf").read_text()
ALL = "\n".join(p.read_text() for p in ROOT.glob("*.tf"))

def has(text, snippet):
    return re.sub(r"\s+", "", snippet) in re.sub(r"\s+", "", text)

HCL_FILES = sorted(ROOT.glob("*.tf")) + sorted(ROOT.glob("*.tfvars.example")) + sorted((ROOT / "tests").glob("*.tftest.hcl"))

def has_split_operator(text):
    # Focused regression guard only, not an HCL lexer/parser.
    return re.search(r"[=!<>][ \t]+=[ \t]*", text) is not None

checks = {
    "no split comparison operators in any HCL file": all(not has_split_operator(p.read_text()) for p in HCL_FILES),
    "FQDN lowercase check uses intact equality": "fqdn == lower(fqdn)" in (ROOT / "variables.tf").read_text(),
    "split-operator guard detects original regression": has_split_operator("fqdn = = lower(fqdn)"),
    "provider exact pin": has(VERSIONS, 'version = "= 5.12.0"'),
    "no automatic provider registration": has(VERSIONS, 'resource_provider_registrations = "none"'),
    "computed firewall address": has(MAIN, 'firewall_ip    = azurerm_firewall.egress.ip_configuration[0].private_ip_address'),
    "explicit private workload subnet": has(MAIN, 'default_outbound_access_enabled = false'),
    "firewall DNS proxy": has(MAIN, 'proxy_enabled = true'),
    "spoke DNS uses firewall": has(MAIN, 'dns_servers         = [local.firewall_ip]'),
    "network mode mutually exclusive": has(MAIN, 'for_each = var.policy_mode == "network" ? [1] : []'),
    "application mode mutually exclusive": has(MAIN, 'for_each = var.policy_mode == "application" ? [1] : []'),
    "network allow only TCP443": has(MAIN, 'destination_ports = ["443"]'),
    "route references computed firewall": has(MAIN, 'next_hop_in_ip_address = local.firewall_ip'),
    "subnet route association": has(MAIN, 'route_table_id = azurerm_route_table.spoke.id'),
    "subnet NSG association": has(MAIN, 'network_security_group_id = azurerm_network_security_group.workload.id'),
    "both forwarded peering flags": len(re.findall(r'allow_forwarded_traffic\s*=\s*true', MAIN)) == 2,
    "strict platform DNS rule": has(MAIN, 'destination_address_prefix = "AzurePlatformDNS"'),
    "password login disabled": has(MAIN, 'disable_password_authentication = true'),
    "no private key resource": 'tls_private_key' not in ALL,
    "no Terraform provisioner": re.search(r'\bprovisioner\s+"', ALL) is None,
    "no NAT gateway resource": re.search(r'resource\s+"azurerm_nat_gateway"', ALL) is None,
    "no DNAT collection": re.search(r'(?m)^\s*nat_rule_collection\s*\{', ALL) is None,
    "Bastion Standard tunnel": has(MGMT, 'tunneling_enabled   = true') and has(MGMT, 'sku                 = "Standard"'),
    "resource-specific logs": has(DIAG, 'log_analytics_destination_type = "Dedicated"'),
    "required log categories": all(has(DIAG, f'"{c}"') for c in ['AZFWNetworkRule', 'AZFWApplicationRule', 'AZFWDnsQuery', 'AZFWThreatIntel']),
}
# Inspect only the workload NIC block (not the firewall/Bastion public IP blocks).
nic = MAIN.split('resource "azurerm_network_interface" "workload" {', 1)[1].split('resource "azurerm_linux_virtual_machine"', 1)[0]
checks["workload NIC has no public IP field"] = 'public_ip_address_id' not in nic
hub = ipaddress.ip_network('10.10.0.0/16')
spoke = ipaddress.ip_network('10.20.0.0/16')
checks["nonoverlapping VNet CIDRs"] = not hub.overlaps(spoke)
checks["firewall subnet is /26 in hub"] = ipaddress.ip_network('10.10.0.0/26').subnet_of(hub)
checks["Bastion subnet is separate /26"] = not ipaddress.ip_network('10.10.1.0/26').overlaps(ipaddress.ip_network('10.10.0.0/26'))
checks["VM IP is usable inside workload subnet"] = ipaddress.ip_address('10.20.1.4') in ipaddress.ip_network('10.20.1.0/24')
for label, passed in checks.items():
    print(f'{"PASS" if passed else "FAIL"}: {label}')
if not all(checks.values()):
    raise SystemExit(1)
print(f'{len(checks)} source-contract checks passed. This is NOT Terraform/provider or runtime validation.')
