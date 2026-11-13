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

GATES = ["deploy_vms", "deploy_storage", "deploy_private_endpoint", "deploy_se_policy", "deploy_pls"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

for sw in ["disable_public_access", "attach_se_policy", "pe_nsg_deny_se", "enable_proxy_protocol"]:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % sw, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("switch %s must exist and default to false" % sw)

if not re.search(r'variable\s+"pls_nat_ip_count"\s*\{.*?default\s*=\s*1\b', tf["variables.tf"], re.S):
    problems.append("pls_nat_ip_count must default to 1")

if not re.search(r'variable\s+"break_fix"\s*\{.*?default\s*=\s*"none"', tf["variables.tf"], re.S):
    problems.append("break_fix must default to none")

for value in ["public_open", "pe_pending", "zone_unlinked", "pls_pending", "nsg_ignored"]:
    if not any(re.search(r'break_fix\s*[=!]=\s*"%s"' % value, text) for text in tf.values()):
        problems.append("break_fix value %s is not used by any resource" % value)

if not re.search(r'service_endpoints\s*=\s*\[\s*"Microsoft\.Storage"\s*\]', tf["main.tf"]):
    problems.append("snet-se must enable the Microsoft.Storage service endpoint")

if not re.search(r'sku\s*=\s*"Standard"', tf["pls.tf"]):
    problems.append("the load balancer behind the Private Link Service must be Standard")

if not re.search(r'default_action\s*=\s*var\.break_fix\s*==\s*"public_open"\s*\?\s*"Allow"\s*:\s*"Deny"', tf["storage.tf"]):
    problems.append("the storage firewall must default to Deny unless break_fix is public_open")

if not re.search(r'private_endpoint_network_policies\s*=', tf["main.tf"]):
    problems.append("snet-pe must set private_endpoint_network_policies explicitly")

for fname, text in tf.items():
    if re.search(r"(admin_password|shared_key|account_key|sas_token)\s*=\s*\"", text):
        problems.append("%s hard-codes a secret" % fname)

for rng in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", alltf):
    if not (rng.startswith(("10.", "0.0.0.0", "00000000"))):
        problems.append("unexpected address %s" % rng)

if problems:
    print("\n".join(sorted(set(problems))))
    sys.exit(1)
print("ok: %d gates default false, break_fix defaults to none, storage firewall defaults to Deny" % len(GATES))
