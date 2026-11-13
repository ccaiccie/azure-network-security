# Scenario 06 actual-results worksheet

**All Azure/guest/NVA/HA observations initially NOT RUN.** Populate only from a separately authorized execution. Never substitute the local mock results for these rows.

- Operator, UTC start/end, approved subscription, RG, region, exact source/lock/image hashes:
- Approval/budget boundaries; installed approved tool versions; image validation:
- Azure deployment and provider schema validated? Record actual errors, not assumptions:
- Actual zones, frontend/pool/rule/probe settings, NIC forwarding flags:
- Effective routes A→B / B→A to same F; NVA fabric routes to both spokes; no recursion:
- Exact effective NSGs and guest rules/sysctls, no NAT or conflicting legacy filters:
- B local8080/8081 readiness and journal UTC:
- Initial closed health; per-node activation and advertisement UTC:

| Case | Client case / attempted tuple / start-end UTC | Proven owner and both-direction evidence | LB eligibility / metric window | B identity or reason HTTP never arrived | Actual outcome |
|---|---|---|---|---|---|
| nva1-only8080 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| nva1-only8081 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| nva2-only8080 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| nva2-only8081 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| both-eligible fresh samples | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| health withdrawal old stream | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| health withdrawal fresh flow | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| forwarding failure old stream | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| forwarding failure fresh flow | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| all withdrawn fresh flow | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| restored8080 / denied8081 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

For each stream retain first/last frame, contiguous sequence, final marker, actual duration, socket timeout/error, and no-reconnect proof. Do not call partial identity-match frames a surviving stream. For an 8081 connect failure, retain attempted source port; no HTTP case header could reach B before connection establishment.

- Failure events path and started/restored/restore-failed UTC; original/restored flags:
- Any SIGKILL/reboot/manual recovery, pending record, policy drift or recovery error:
- Snapshot/capture artifacts on BOTH nodes, client connection/result/frames, backend journal:
- Metric timing/granularity limitations; missing evidence and alternative explanations:
- Cleanup approval/plan/resource deletion verification; retained external image and key:
- Actual limitations, blockers and any claims still NOT PROVEN:
