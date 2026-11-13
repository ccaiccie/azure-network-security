"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
problems = []

GATES = ["deploy_vms", "deploy_monitoring", "deploy_flow_logs", "deploy_connection_monitor", "deploy_firewall"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

for name, want in (("nsg_allows_app_port", "true"), ("symmetric_return", "true"), ("traffic_analytics_enabled", "true"), ("create_network_watcher", "false")):
    if not re.search(r'variable\s+"%s"\s*\{.*?default\s*=\s*%s' % (name, want), tf["variables.tf"], re.S):
        problems.append("%s must default to %s" % (name, want))
if not re.search(r'variable\s+"monitor_protocol"\s*\{.*?default\s*=\s*"Tcp"', tf["variables.tf"], re.S):
    problems.append("monitor_protocol must default to Tcp")

# the billable resources must sit behind a gate (count or for_each)
for fname in ("monitoring.tf", "flowlogs.tf", "connmon.tf", "firewall.tf", "vms.tf"):
    for m in re.finditer(r'resource\s+"(azurerm_\w+|random_string)"\s+"\w+"\s*\{(.*?)\n\}', tf[fname], re.S):
        if not re.search(r"(count|for_each)\s*=", m.group(2)):
            problems.append("%s: %s has no count or for_each gate" % (fname, m.group(1)))

# the only public IP is the firewall's
for fname, text in tf.items():
    if re.search(r'resource\s+"azurerm_public_ip"', text) and fname != "firewall.tf":
        problems.append("%s creates a public IP: only firewall.tf may" % fname)

if not re.search(r"dynamic\s+\"traffic_analytics\"", tf["flowlogs.tf"]):
    problems.append("traffic analytics must be switchable")
if not re.search(r'log_analytics_destination_type\s*=\s*"Dedicated"', tf["firewall.tf"]):
    problems.append("the firewall diagnostic setting must use Dedicated tables")
if not re.search(r"var\.symmetric_return", tf["firewall.tf"]):
    problems.append("firewall.tf must use symmetric_return")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("ok: %d gates default false, billable resources are gated, one public IP (firewall)" % len(GATES))
