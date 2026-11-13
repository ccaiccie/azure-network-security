# DNAT operator evidence record

**Template only. No Azure result was captured during drafting.** Every row starts NOT RUN.

- Operator / authorized subscription, region and dedicated RG:
- Approved publication window / spending / deletion time:
- Terraform/AzureRM version and genuine lock verification:
- Concrete image version / runtime readiness:
- Actual P / F / firewall ID / policy association:
- Allowed C/32, how actual source was verified, observed public c:
- B VM/NIC/private IP identity:
- Observed instance I / backend source port q per case:
- Flags: publish_dnat / enable_default_route / return_route_blackhole:
- UTC window, local clock agreement and log ingestion status:

| Check | Status | Actual observation | Evidence path / case / UTC |
|---|---|---|---|
| Approved actual /32; no wildcard/documentation/private source | NOT RUN | | |
| Correct P, group 200 / collection 100/operator-only mapping 8443→8080 | NOT RUN | Plain HTTP, not TLS | |
| Backend private subnet/no NIC public IP | NOT RUN | | |
| Both Connected forwarded-traffic peerings | NOT RUN | | |
| Firewall/Bastion no workload UDR; correct backend table association | NOT RUN | | |
| Backend effective NSG allows firewall /26→B:8080 and Bastion /26→B:22 | NOT RUN | No public-client-source backend service allow | |
| Owned local B:8080 listener active, HTTP200 and correct JSON | NOT RUN | Local readiness peer B is normal | |
| Positive external HTTP200 and exact case/B/port | NOT RUN | | |
| Positive backend peer I is in 10.0.1.0/26; q observed | NOT RUN | Do not require I=F or I=C or q=c | |
| Matching NAT rule row for original C:c→P8443, translated B:8080 | NOT RUN | No Action/translated-source column expected | |
| Backend journal correlates external case and I:q | NOT RUN | | |
| Effective backend return route to observed I selects hub-peering /16 | NOT RUN | /0→F is less specific | |
| Optional next-hop query to observed I | NOT RUN | Requires existing authorized Network Watcher | |
| Public8444 unpublished negative plus healthy 8443 controls | NOT RUN | No NAT Deny expected | |
| Second controlled actual excluded source verified | NOT RUN | Another device behind same NAT is insufficient | |
| Excluded source negative with healthy allowed controls | NOT RUN | No NAT match by itself is not proof | |
| Optional bounded backend/client capture | NOT RUN | No tool installed or capture run by draft | |
| Optional owned listener stop contrast and restoration | NOT RUN | NAT match does not prove listener success | |
| Optional /0 removal leaves hub-peering return to I | NOT RUN | Removal does not inherently break DNAT reply | |
| Optional firewall-subnet /26→None blackhole | NOT RUN | Routing failure, not policy Deny; fresh handshake can fail before any HTTP journal row | |
| Restore routes/owned listener and full published acceptance | NOT RUN | | |
| Withdraw publication; new requests no longer reach fixture | NOT RUN | Not proof all existing sessions were killed | |
| Cleanup: empty state, absent RG and no billable lab resources | NOT RUN | Withdrawal/VM stop alone not cleanup | |

Use only PASSED, FAILED, INCONCLUSIVE or NOT RUN. A failed curl or absent NAT row is not a complete security verdict. Negatives require healthy controls, verified actual source where applicable, current narrow configuration and supporting server/available firewall evidence. Missing optional observations stay NOT RUN. Never silently turn skipped tests into passes.

## Restrictions, unexpected results and unresolved observations

## Rollback and cleanup confirmation

## Evidence retained and redacted before sharing
