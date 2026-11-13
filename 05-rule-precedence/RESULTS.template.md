# Scenario05 evidence record

**All Azure/runtime outcomes default NOT RUN.** Local source/loopback/mock passes cannot fill these fields. No secrets, full state, credentials or real user data belong here.

## Configuration and controls

- Approved subscription / region / UTC / operator:
- Terraform/provider versions and reviewed lockfile; pinned VM image:
- Dedicated RG / actual Firewall ID / policy association:
- A=10.10.1.10 / B=10.20.1.10 / observed F / service P (not private proxy source):
- Actual deployment/readiness/mode/experiment flags and reviewed change references:
- Four peerings, two remote-prefix UDRs/defaults, actual NIC effective route evidence:
- Actual dual-source backend NSGs, app8080/8081 envelope and Bastion/DNS rules:
- Hub private-zone link, records, VM resolver configuration and lookup evidence:
- Backend local four controls: both names on8080/8081, services active and fixed JSON:
- Diagnostic category/destination/retention evidence:

## Fresh-connection cases

| Mode/case | UTC / case ID / client source port | Actual HTTP and fixture identity | Exact deciding rule/action | B transport peer/port and path | Outcome |
|---|---|---|---|---|---|
| closed / allowed |NOT RUN|NOT RUN|NOT RUN|NOT RUN|NOT RUN |
| application / allowed |NOT RUN|NOT RUN|allow-approved-host expected|I in firewall subnet expected|NOT RUN |
| application / denied |NOT RUN|NOT RUN|deny-denied-host expected|No successful case, with positive controls|NOT RUN |
| application /8081 |NOT RUN|NOT RUN|deny-app-alternate-port expected|Healthy local8081 control required|NOT RUN |
| network-allow / allowed |NOT RUN|NOT RUN|allow-app-backend expected|A expected|NOT RUN |
| network-allow / denied |NOT RUN|NOT RUN|allow-app-backend expected|A expected despite app Deny configured|NOT RUN |
| network-allow /8081 |NOT RUN|NOT RUN|deny-app-alternate-port expected|Healthy control required|NOT RUN |
| network-deny / allowed |NOT RUN|NOT RUN|deny-app-backend expected|No successful case|NOT RUN |
| network-deny / denied |NOT RUN|NOT RUN|deny-app-backend expected|No successful case|NOT RUN |
| application restored / allowed |NOT RUN|NOT RUN|allow-approved-host expected|I expected again|NOT RUN |
| application restored / denied |NOT RUN|NOT RUN|deny-denied-host expected|No successful case|NOT RUN |
| application restored /8081 |NOT RUN|NOT RUN|deny-app-alternate-port expected|Healthy control required|NOT RUN |

- Actual I and q, never assumed equal to F or client port:
- B→A remote UDR versus B→I hub-peering effective route comparison:
- Backend XFF observations explicitly untrusted and separate from socket peer:
- Retained positive controls before/after denies and logging latency/window:
- Unexpected errors, mismatches, missing evidence and unresolved claim:
- Conceptual only/NOT IMPLEMENTED: inheritance, DNAT, Premium TLS/IDPS, reverse-new, generic Internet/DNS/QUIC bypass suite.

## Restoration and removal

- Network override removed and fresh application positive/negative/source transition observed:
- Closed-policy rollback if used; billing still active until resources removed:
- SSH/tunnels stopped:
- Dedicated destruction approved/reviewed and actual removal/billing leftovers checked:
- Evidence retention/location/access:
