"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
problems = []

GATES = ["deploy_vms", "deploy_custom_dns", "deploy_private_endpoint", "create_public_zone"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

if not re.search(r'variable\s+"break_fix"\s*\{.*?default\s*=\s*"none"', tf["variables.tf"], re.S):
    problems.append("break_fix must default to none")

for value in ["no_spoke_link", "no_zone_group", "pe_zone_unlinked", "public_forwarder", "stale_record"]:
    if not any(re.search(r'break_fix\s*[=!]=\s*"%s"' % value, text) for text in tf.values()):
        problems.append("break_fix value %s is not used by any resource" % value)

links = re.findall(r'resource\s+"azurerm_private_dns_zone_virtual_network_link"\s+"(\w+)"', "".join(tf.values()))
for need in ["app", "spoke", "blob_app", "blob_spoke"]:
    if need not in links:
        problems.append("missing zone link resource %s" % need)

for name in links:
    for text in tf.values():
        block = re.search(r'resource\s+"azurerm_private_dns_zone_virtual_network_link"\s+"%s"\s*\{(.*?)\n\}' % name, text, re.S)
        if block and not re.search(r"registration_enabled\s*=", block.group(1)):
            problems.append("link %s does not set registration_enabled explicitly" % name)

reg = re.search(r'resource\s+"azurerm_private_dns_zone_virtual_network_link"\s+"app"\s*\{(.*?)\n\}', tf["main.tf"], re.S)
if not reg or not re.search(r"registration_enabled\s*=\s*true", reg.group(1)):
    problems.append("the app link must have registration_enabled = true")

for fname, text in tf.items():
    if re.search(r"(admin_password|shared_key|account_key)\s*=\s*\"", text):
        problems.append("%s hard-codes a secret" % fname)

for rng in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "".join(tf.values())):
    if not (rng.startswith(("10.", "203.0.113.", "168.63.129.16", "9.9.9.9", "0.0.0.0", "00000000"))):
        problems.append("unexpected address %s" % rng)

if problems:
    print("\n".join(sorted(set(problems))))
    sys.exit(1)
print("ok: %d gates default false, %d link resources, break_fix defaults to none" % (len(GATES), len(links)))
