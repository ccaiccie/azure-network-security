"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
problems = []

GATES = ["deploy_vms", "enable_ha_ports_rule", "create_nat_rule", "create_public_lb", "create_global_lb", "floating_ip"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

for name, want in (("break_fix", "none"), ("session_persistence", "Default")):
    m = re.search(r'variable\s+"%s"\s*\{.*?default\s*=\s*"%s"' % (name, want), tf["variables.tf"], re.S)
    if not m:
        problems.append("%s must default to %s" % (name, want))

for sku in re.findall(r'resource\s+"azurerm_lb"\s+"\w+"\s*\{(.*?)\n\}', tf["lb.tf"] + tf["public.tf"], re.S):
    if not re.search(r'sku\s*=\s*"Standard"', sku):
        problems.append("every load balancer must use the Standard SKU")

ha = re.search(r'resource\s+"azurerm_lb_rule"\s+"ha_ports"\s*\{(.*?)\n\}', tf["lb.tf"], re.S)
if not ha or not (re.search(r'protocol\s*=\s*"All"', ha.group(1)) and re.search(r"frontend_port\s*=\s*0", ha.group(1))):
    problems.append("the HA ports rule must use protocol All and port 0")

rule = re.search(r'resource\s+"azurerm_lb_rule"\s+"http"\s*\{(.*?)\n\}', tf["lb.tf"], re.S)
if not rule or not re.search(r"floating_ip_enabled\s*=\s*var\.floating_ip", rule.group(1)):
    problems.append("the main rule must take floating_ip_enabled from var.floating_ip")
if rule and not re.search(r"frontend_port\s*=\s*80", rule.group(1)):
    problems.append("the main rule frontend port must be 80 (floating IP needs equal ports)")

for fname, text in tf.items():
    if re.search(r"resource\s+\"azurerm_public_ip\"", text) and fname not in ("public.tf",):
        problems.append("%s creates a public IP outside the gated file public.tf" % fname)

if not re.search(r"count\s*=\s*var\.create_public_lb", tf["public.tf"]):
    problems.append("public.tf resources must be gated by create_public_lb")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("ok: %d gates default false, break_fix defaults to none, all load balancers are Standard" % len(GATES))
