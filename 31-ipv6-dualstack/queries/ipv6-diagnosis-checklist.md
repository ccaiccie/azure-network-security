# IPv6 diagnosis checklist (designed, not tested)

Ask in this order. Stop at the first answer that explains the symptom. The three layers are the name, the path and the rules.

1. Name: does the name have an AAAA record? `./scripts/diagnose.sh dns` and `./scripts/diagnose.sh resolve VM NAME`. No AAAA means a client simply uses IPv4 (or fails if it has no IPv4).
2. Address: does the NIC have an IPv6 configuration, and does the guest have the address and a default route? `./scripts/diagnose.sh nic VM` and `./scripts/diagnose.sh v6 VM`.
3. Force the family: `curl -4` and `curl -6` to the same name or address. Different results show which layer is family-specific.
4. NSG: is there a rule that matches the IPv6 source and destination? An IPv4 prefix never matches an IPv6 packet. `./scripts/diagnose.sh nsg`.
5. Routes: compare the IPv4 rows and the IPv6 rows of `./scripts/diagnose.sh routes VM`. A UDR written for 0.0.0.0/0 does nothing for IPv6; a ::/0 route must be written on purpose.
6. Load balancer: both a frontend and a rule for each family, and a backend pool that holds the IPv6 IP configuration. `./scripts/diagnose.sh lb`.
7. Inspection device: does the firewall or appliance support IPv6 and have an IPv6 policy? A device that sees only IPv4 may drop the IPv6 half of a flow. Check current Microsoft docs and the vendor.
8. Return path: the reply must pass the same stateful device. Compare the next hop of the forward and return routes.
9. Check current Microsoft docs for limits and service support before relying on them.
