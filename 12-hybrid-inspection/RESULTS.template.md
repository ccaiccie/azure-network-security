# Scenario12 observation worksheet

**Every runtime entry starts NOT RUN. Do not copy mock results into this table as Azure evidence.** Store privately; omit PSK, raw state/plan and secret-bearing API bodies. Review metadata/error text before sharing a sanitized copy.

## Ownership and preparation

- Authorized operator/change record and UTC window: NOT RUN
- Approved subscription/RG/region, current quota/capacity/cost estimate: NOT RUN
- Exact approved image version and required tool/guest baseline verification: NOT RUN
- Genuine Terraform/provider version, lock digest, fmt/validate/mock-plan results: NOT RUN
- Protected secret injection/backend/plan/state/backup workflow approved, with no key value recorded here: NOT RUN
- Exact source/package digest: NOT RUN

## Actual resources, control and routes

- Four VNet IDs, exact subnet prefixes and two VM/NIC IDs: NOT RUN
- Two VpnGw1AZ active-standby/non-BGP gateways and actual public endpoint addresses: NOT RUN
- Reciprocal connection IDs/peer IDs and observed connection/tunnel status (sanitized source/UTC): NOT RUN
- Connection GET skipped or explicitly acknowledged, API/CLI versions, incomplete/null/error evidence: NOT RUN
- F actual allocated private IP; firewall/policy/group/rule names/actions/priorities: NOT RUN
- GatewaySubnet exact10.20/16→F, propagation true, no NSG/default/control-prefix overlap: NOT RUN
- A effective route to B selects propagated spoke gateway route; actual source/type/next-hop fields: NOT RUN
- B effective route to A172.16/16→F and propagation false, no more-specific bypass: NOT RUN
- Firewall onward routes to B by peering and A by VPN, supported evidence and unresolved gaps: NOT RUN
- Actual NSG test envelopes, no NAT/default forced route and management return paths: NOT RUN
- Local healthy A8082/B8080/B8081 fixture/readiness and startup units: NOT RUN
- Firewall logs, gateway diagnostic schema/metrics/ingestion observed: NOT RUN

## Per-flow evidence

| Case | UTC start/end and immutable directory | Attempted tuple and stages | Local readiness/routes/NSGs | Firewall exact rule/action | Endpoint identity/source | Verdict |
|---|---|---|---|---|---|---|
| Primary closed8080 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Primary allowed8080 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Alternate8081 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Reverse-new B→A8082 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Held stream and primary closure | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Fresh flow after closure | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

A denied SYN has no HTTP case header; correlate bound source port/destination/time. `Connected`, HTTP200, empty logs and timeout each remain insufficient by themselves. Record packet inner tuple separately from VPN outer gateway endpoints. Record old-stream and new-flow outcomes independently; no guaranteed timing or session continuity.

## Teardown

- Clients stopped/finite streams ended, Firewall Deny effective: NOT RUN
- Exact listener units inactive and successful ss query empty on both VMs: NOT RUN
- Exact NSGs closed; old sessions ended and independent management retained: NOT RUN
- Isolation proven before any steering/connection removal; reviewed dependency plan: NOT RUN
- Connection-removal stage clears connections_ready/create_connections, withdraws PSK input to null and retains closed substrate/management: NOT RUN
- Both owned connections/gateways/firewall/VMs/disks/routes/peerings/Bastions/public IPs/logging deleted as authorized: NOT RUN
- Residual resources/charges and secure secret/state/evidence disposition: NOT RUN

Real branch S2S equipment, BGP, ExpressRoute/private peering/carrier, FastPath, backup transport/failover and a state-free external-connection mode: **NOT IMPLEMENTED / NOT TESTED**.
