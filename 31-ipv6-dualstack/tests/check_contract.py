"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
alltf = "\n".join(tf.values())
problems = []

GATES = ["deploy_vms", "deploy_lb", "deploy_client_ips", "deploy_peer"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

if not re.search(r'variable\s+"break_fix"\s*\{.*?default\s*=\s*"none"', tf["variables.tf"], re.S):
    problems.append("break_fix must default to none")

for value in ["nsg_v4_only", "no_aaaa", "udr_v4_only"]:
    if not any(re.search(r'break_fix\s*[=!]=\s*"%s"' % value, text) for text in tf.values()):
        problems.append("break_fix value %s is not used by any resource" % value)

if not re.search(r'address_space\s*=\s*\[\s*var\.ipv4_vnet_prefix\s*,\s*var\.ipv6_vnet_prefix\s*\]', tf["main.tf"]):
    problems.append("the main VNet must carry an IPv4 and an IPv6 address space")

if not re.search(r'cidrsubnet\s*\(\s*var\.ipv6_vnet_prefix\s*,\s*16\s*,', tf["main.tf"]):
    problems.append("IPv6 subnets must be /64 carved from the /48 (cidrsubnet with 16 new bits)")

if not re.search(r'private_ip_address_version\s*=\s*"IPv6"', tf["vms.tf"]):
    problems.append("the NIC needs a second IP configuration with private_ip_address_version IPv6")

for name in ("lb_v4", "lb_v6"):
    if not re.search(r'resource\s+"azurerm_public_ip"\s+"%s"\s*\{.*?sku\s*=\s*"Standard"' % name, tf["lb.tf"], re.S):
        problems.append("public IP %s must be Standard" % name)

if not re.search(r'ip_version\s*=\s*"IPv6"', tf["lb.tf"]):
    problems.append("the load balancer needs an IPv6 public IP")

if not re.search(r'source_address_prefix\s*=\s*"::/0"', tf["main.tf"]):
    problems.append("the NSG needs an IPv6 allow rule with source ::/0")

for fname, text in tf.items():
    if re.search(r"(admin_password|shared_key|account_key|sas_token)\s*=\s*\"", text):
        problems.append("%s hard-codes a secret" % fname)

for rng in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", alltf):
    if not (rng.startswith(("10.", "0.0.0.0"))):
        problems.append("unexpected IPv4 address %s" % rng)

for v6 in re.findall(r"\b[0-9a-f]{1,4}(?::[0-9a-f]{0,4}){2,7}\b", alltf, re.I):
    if not v6.lower().startswith(("2001:db8", "fd00:db8")):
        problems.append("IPv6 example outside 2001:db8::/32 or the ULA example: %s" % v6)

if problems:
    print("\n".join(sorted(set(problems))))
    sys.exit(1)
print("ok: %d gates default false, break_fix defaults to none, IPv6 examples use the documentation prefix" % len(GATES))
