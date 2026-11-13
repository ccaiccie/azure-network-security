#!/usr/bin/env python3
"""Designed, not tested. Offline helpers for the ExpressRoute lab. They never call Azure.

  er-tools.py overlap <global-reach-/29> <prefix> [<prefix> ...]
  er-tools.py capacity <port-gbps> <circuit-gbps> [<circuit-gbps> ...]
  er-tools.py triage <fixture.json>
"""
import ipaddress
import json
import sys


def overlap(argv):
    if len(argv) < 2:
        sys.exit("usage: er-tools.py overlap <range> <prefix> [<prefix> ...]")
    rng = ipaddress.ip_network(argv[0], strict=True)
    bad = False
    if rng.prefixlen != 29:
        print(f"PROBLEM: {rng} is a /{rng.prefixlen}, Global Reach needs a /29")
        bad = True
    for p in argv[1:]:
        net = ipaddress.ip_network(p, strict=False)
        if rng.overlaps(net):
            where = "inside" if rng.subnet_of(net) else "overlapping"
            print(f"OVERLAP: {rng} is {where} {net}")
            bad = True
    if not bad:
        halves = list(rng.subnets(new_prefix=30))
        print(f"OK: {rng} is a /29 and overlaps nothing in the list")
        print("Link networks: " + " and ".join(str(h) for h in halves))
    return 1 if bad else 0


def capacity(argv):
    if len(argv) < 2:
        sys.exit("usage: er-tools.py capacity <port-gbps> <circuit-gbps> ...")
    port = float(argv[0])
    circuits = [float(x) for x in argv[1:]]
    total = sum(circuits)
    ratio = total / port
    print(f"Port {port:g} Gbps, circuits total {total:g} Gbps, ratio {ratio:.2f}")
    if ratio <= 1:
        print("OK: within the port size, no contention")
    elif ratio <= 2:
        print("OVERSUBSCRIBED: allowed only if the current limit permits it (documentation has said about 2x). "
              "Watch the dropped-bits metrics; peaks can lose packets. Check current Microsoft docs.")
    else:
        print("REFUSED: above about 2x. Add a port pair or shrink the circuits. Check current Microsoft docs.")
    return 0


def triage(argv):
    if len(argv) != 1:
        sys.exit("usage: er-tools.py triage <fixture.json>")
    with open(argv[0], encoding="utf-8") as f:
        d = json.load(f)
    print("Case:", d["case"])
    print("Symptom:", d["symptom"])
    print("Evidence:")
    for k, v in d["evidence"].items():
        print(f"  {k}: {v}")
    ev = d["evidence"]
    findings = []
    if ev.get("provider_state") not in (None, "Provisioned"):
        findings.append("Provider state is not Provisioned: physical or provider layer first.")
    for path in ("primary", "secondary"):
        arp, bgp = ev.get(f"arp_{path}"), ev.get(f"bgp_{path}")
        if arp == "up" and bgp not in (None, "Established"):
            findings.append(f"{path}: ARP is up but BGP is {bgp}: layer 2 works, check ASN, link /30, MD5 and filters.")
    if ev.get("fastpath_flag") is True and ev.get("gateway_pps_follows_traffic") is True:
        findings.append("FastPath flag is true but the gateway packet rate follows the traffic: the data still crosses the gateway. "
                        f"Check the destination type ({ev.get('destination', 'unknown')}) and the gateway SKU.")
    if ev.get("gateway_cpu_percent", 0) >= 80 and ev.get("circuit_utilisation_percent", 100) < 60:
        findings.append("Gateway CPU is high while the circuit is quiet: the gateway is the bottleneck. Resize, ErGwScale or FastPath.")
    if ev.get("overlap_with"):
        findings.append(f"Overlap: {ev['overlap_with']}. Remove or renumber, and re-run the overlap check.")
    print("Diagnosis:")
    for x in findings or ["Nothing matched: widen the evidence."]:
        print("  -", x)
    print("Expected answer:", d["answer"])
    return 0


def main():
    cmds = {"overlap": overlap, "capacity": capacity, "triage": triage}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))


if __name__ == "__main__":
    main()
