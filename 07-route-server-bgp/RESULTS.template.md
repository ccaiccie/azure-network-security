# Scenario 07 actual-results worksheet

All Azure/FRR/GRE/kernel observations begin **NOT RUN**. Source/mock/loopback tests cannot populate these rows.

- Operator, approvals, UTC start/end, subscription/RG/region, source/lock/image hashes:
- Exact FRR/kernel/tool versions, image provenance and service baseline:
- Actual RS ASN and two peer addresses; both connection objects and four sessions:
- No RS subnet NSG/UDR, app propagation on, NVA/remote propagation off:
- Exact guest FIB/owned nft/sysctls, no recursive route or unrelated configuration:
- Local R loopback plus8080/8081 fixture readiness and journal:

| Case | Client attempted/successful tuple and UTC | Both-instance BGP/export/path evidence | A effective selected route | Original/SNAT/GRE/reverse capture + conntrack | Actual outcome |
|---|---|---|---|---|---|
| Closed baseline | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Preferred8080 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Healthy remote8081 denied | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| NVA1 both-peer withdrawal, fresh flow | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| NVA1 withdrawal, original stream | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| One RS session down | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Forward policy closed, BGP alive | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Both nodes withdrawn | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Restored8080 / denied8081 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

- R observed overlay source and actual translated port q per connection; identity/case:
- Old stream first/last frame, final marker/completeness, socket timeout, no-reconnect proof:
- Negative SYN attempted source port and UTC; HTTP-not-sent if connect failed:
- Named deny/counters with remote8081 health; no timeout-only policy claim:
- Each failure event path/start/restore UTC; live lock, interruption/recovery limitations:
- Ordinary transition marker, partial-peer/state-write failures, reconcile local verification and separate Azure withdrawal proof:
- Restoration failure safety attempts and explicit uncertainty; pending record disposition:
- Metric definitions/window/dimensions; aggregate counts do not prove data forwarding:
- Missing evidence / alternative explanations / INCONCLUSIVE cases:
- Withdrawal verified before cleanup, approved deletion, resource/billing verification:
