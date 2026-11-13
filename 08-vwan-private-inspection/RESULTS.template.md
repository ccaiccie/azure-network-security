# Scenario 08 operator evidence worksheet

**All actual Azure/guest outcomes below: NOT RUN.** This file is a template, not fabricated evidence. Local source/mock/loopback validation is separately recorded under validation/.

## Context

- Approved subscription, region, operator and UTC window: NOT RUN
- Exact provider version and genuine lock digest; actual fmt/validate/mock-test result: NOT RUN
- Approved Compute Gallery version; image tools/guest-policy checks: NOT RUN
- Reviewed plan/change authorization and cost budget: NOT RUN
- Actual WAN/hub/F/policy/intent IDs and F private/public IPs: NOT RUN
- Protected evidence location, controls and retention: NOT RUN

## Readiness and route proof

- A8082 and B8080/8081 readiness/config/NIC/units/listeners/local identity: NOT RUN
- Before/after collector paths, completed UTC, failures and any partial reads: NOT RUN
- Both workload NIC effective routes/NSGs; selected destination prefixes and actual next hops: NOT RUN
- Workload /0->None, private propagation and no bypass/stronger UDR: NOT RUN
- Intent next-hop F ID, PrivateTraffic only, both connection association/propagation: NOT RUN
- DefaultRouteTable route view and selected entity/UTC: NOT RUN
- **Firewall onward effective routes to both app and backend**; selected F ID/UTC/prefix/type/next hop/origin: NOT RUN
- No competing connection routing ownership; refreshed plan/drift review: NOT RUN
- Both Bastion subnet independence and private SSH access: NOT RUN
- Actual NSG priority100/101 action before each test: NOT RUN

## Per-case evidence

Fill one new row/group per attempt, never overwrite earlier files. Record result.json, connection.json, optional connected/request/frames, fixture journal and actual AZFWNetworkRule row. Copy actual tuple and timestamps, not just the mode label.

| Case | Requested gates | Expected review target | Actual outcome |
|---|---|---|---|
| Initial isolation | NSG Deny, Firewall Deny | Isolation only; not named Firewall-deny proof | NOT RUN |
| closed A→B8080 | NSG Allow, Firewall Deny | Named test-flow Deny and healthy B8080 | NOT RUN |
| positive A→B8080 | NSG Allow, Firewall Allow | Exact fixture, original IP/port, Network Allow and journal | NOT RUN |
| alternate A→B8081 | NSG Allow, Firewall primary Allow | Healthy B8081, named deny-app-alt-8081 Deny | NOT RUN |
| reverse B→A8082 | NSG Allow, Firewall primary Allow | Healthy A8082, named deny-backend-new-8082 Deny | NOT RUN |
| held-open stream | Primary Allow then Deny | One tuple; frame/cutoff time vs actual policy effectiveness | NOT RUN |
| restored closed fresh flow | NSG Allow, Firewall Deny | New tuple, stable named Deny after change effective | NOT RUN |
| pre-destroy isolation | Clients/listeners stopped; F and NSG Deny | Actual closure despite possible stateful NSG residue | NOT RUN |

For each: case ID; attempted_local and attempted_destination; started_utc/completed_utc; TCP connected? HTTP write not-started/attempted/completed? original tuple at fixture? exact Action/Policy/RuleCollectionGroup/RuleCollection/Rule/TimeGenerated/_ResourceId; relevant route snapshot. Logs can arrive late. A missing backend HTTP case is expected if SYN never connected and is not itself proof of Deny. Empty log/API results are inconclusive.

## Rollback and cleanup

- Clients/listeners stopped and verified; held-open flow disposition: NOT RUN
- Primary Firewall action restored to Deny, effective policy and fresh/old flows verified: NOT RUN
- NSG test_paths_enabled=false effective and isolation verified: NOT RUN
- Intent retained until isolation; intent-first inverse deletion risk reviewed: NOT RUN
- Destruction separately authorized and remaining resources/costs checked: NOT RUN
- Existing image/key untouched; protected state/evidence retention handled: NOT RUN

Do not mark the lab successful until all required evidence is available and contradictions are resolved. Report missing or unavailable API views without substituting inferred paths.
