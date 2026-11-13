"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
problems = []

GATES = ["deploy_avnm", "deploy_connectivity", "deploy_security_admin", "deploy_dynamic_group", "deploy_vms", "deploy_second_region"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

for name, want in (("active_connectivity", "v1"), ("admin_rule_action", "Deny")):
    if not re.search(r'variable\s+"%s"\s*\{.*?default\s*=\s*"%s"' % (name, want), tf["variables.tf"], re.S):
        problems.append("%s must default to %s" % (name, want))

if not re.search(r'variable\s+"use_hub_gateway"\s*\{.*?default\s*=\s*false', tf["variables.tf"], re.S):
    problems.append("use_hub_gateway must default to false (the lab hub has no gateway)")

# every AVNM resource must sit behind a gate
for fname in ("avnm.tf", "connectivity.tf", "security.tf", "dynamic.tf", "deploy.tf"):
    for m in re.finditer(r'resource\s+"(azurerm_network_manager\w*|azurerm_policy\w*|azurerm_subscription_policy\w*)"\s+"\w+"\s*\{(.*?)\n\}', tf[fname], re.S):
        if not re.search(r"(count|for_each)\s*=", m.group(2)):
            problems.append("%s: %s has no count or for_each gate" % (fname, m.group(1)))

# the two connectivity configurations differ only in group connectivity
conn = tf["connectivity.tf"]
if not (re.search(r'group_connectivity\s*=\s*"None"', conn) and re.search(r'group_connectivity\s*=\s*"DirectlyConnected"', conn)):
    problems.append("connectivity.tf must hold one None and one DirectlyConnected configuration")

sec = tf["security.tf"]
if not re.search(r"action\s*=\s*var\.admin_rule_action", sec):
    problems.append("the app-port admin rule must take its action from var.admin_rule_action")
if not re.search(r"network_group_ids\s*=", sec):
    problems.append("the rule collection must name its network groups")

if not re.search(r'effect\s*=\s*"addToNetworkGroup"', tf["dynamic.tf"]):
    problems.append("dynamic.tf must use the addToNetworkGroup effect")

for fname, text in tf.items():
    if re.search(r'resource\s+"azurerm_public_ip"', text):
        problems.append("%s creates a public IP: the lab needs none" % fname)

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("ok: %d gates default false, every AVNM resource is gated, no public IPs" % len(GATES))
