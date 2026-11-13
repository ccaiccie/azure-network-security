"""Whitespace-tolerant source checks for the lab. Reads files only: no Terraform, no Azure.

Run:  python3 -I tests/check_contract.py     (from the terraform folder)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tf = {p.name: p.read_text() for p in ROOT.glob("*.tf")}
problems = []

GATES = ["deploy_vms", "peer_spokes_directly", "deploy_nva", "create_global_peering",
         "create_gateway", "enable_gateway_transit", "create_onprem_connection"]
for g in GATES:
    m = re.search(r'variable\s+"%s"\s*\{(.*?)\n\}' % g, tf["variables.tf"], re.S)
    if not m or not re.search(r"default\s*=\s*false", m.group(1)):
        problems.append("gate %s must exist and default to false" % g)

if not re.search(r'variable\s+"break_fix"\s*\{.*?default\s*=\s*"none"', tf["variables.tf"], re.S):
    problems.append("break_fix must default to none")

peerings = re.findall(r'resource\s+"azurerm_virtual_network_peering"\s+"(\w+)"', tf["peering.tf"])
for need in ["hub_to_a", "a_to_hub", "hub_to_b", "b_to_hub", "a_to_b", "b_to_a", "hub_to_c", "c_to_hub"]:
    if need not in peerings:
        problems.append("missing peering resource %s" % need)

for name in ["hub_to_a", "a_to_hub", "hub_to_b", "b_to_hub"]:
    block = re.search(r'resource\s+"azurerm_virtual_network_peering"\s+"%s"\s*\{(.*?)\n\}' % name, tf["peering.tf"], re.S)
    for prop in ["allow_virtual_network_access", "allow_forwarded_traffic", "allow_gateway_transit", "use_remote_gateways"]:
        if not block or not re.search(r"%s\s*=" % prop, block.group(1)):
            problems.append("%s does not set %s explicitly" % (name, prop))

if re.search(r'GatewaySubnet', tf["main.tf"]) and not re.search(r'name\s*=\s*"GatewaySubnet"', tf["main.tf"]):
    problems.append("the gateway subnet must be named exactly GatewaySubnet")

for fname, text in tf.items():
    if re.search(r"shared_key\s*=\s*\"", text):
        problems.append("%s hard-codes a shared key" % fname)

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("ok: %d gates default false, %d peering resources, break_fix defaults to none" % (len(GATES), len(peerings)))
