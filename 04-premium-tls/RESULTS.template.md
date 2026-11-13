# Scenario04 runtime evidence record

**Default status: NOT RUN.** Local mocks are not values for this record. Do not mark a case pass solely because curl failed/succeeded or a query was empty. Never paste secrets, PFX, private keys, auth tokens, full Terraform state or publishing profiles here.

## Actual deployment and approvals

- UTC test window / operator:
- Approved subscription / region / dedicated RG:
- Exact Terraform and AzureRM version / reviewed lockfile checksum:
- Actual pinned VM image / observed guest tool versions:
- Approved existing UAI / versioned CA-secret identifier (identifiers only; handle privately):
- PKI/access/linkage approval reference, retrieval/provisioning status and checked time:
- Approved inspection root public SHA256 fingerprint:
- Separate normal-origin public trust bundle approval/fingerprint and exclusion proof:
- A / F / P / actual H:
- Node package ZIP SHA256 / deployment status / actual Node runtime:
- Operator source32, main-site and SCM restrictions:
- Gates actually deployed, exact policy/group/collection/rules:
- Firewall diagnostics and origin HTTP/Console/IPSec audit settings:

## Controls

- Effective workload0/0→F; other more-specific routes; state-matched subscription:
- Guest resolver actually using F; current H answers:
- Effective app/Bastion NSGs and private management:
- Direct-origin /allowed HTTP200, public certificate/hostname verified, fixture case/path:
- Direct-origin /blocked HTTP200, public certificate/hostname verified, fixture case/path:
- Source-restriction/frontend audit evidence distinguishing operator from P:
- Separate inspection-chain verification/hostname/root fingerprint and tuple/time:

## Cases

| Case | Requested URL / case ID | UTC, User-Agent and actual client tuple | curl exit / HTTP / verify | Exact firewall decision and IsTlsInspected | Origin record / confirmed absence with control | Outcome |
|---|---|---|---|---|---|---|
| Allowed inspection | /allowed | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Exact URL deny | /blocked | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Untrusted inspection root | /allowed | NOT RUN | NOT RUN | Handshake may fail before HTTP decision | No origin receipt required | NOT RUN |
| Optional approved origin pin | /allowed | NOT RUN | NOT RUN | Independent control needed | No origin receipt required | NOT RUN |

- IDPS mode observed: NOT RUN. Signature/action evidence: NOT RUN. A benign empty query is not prevention proof.
- Separate originTLS leg / frontend source evidence: NOT RUN. Do not use Node socket_peer or untrusted XFF as proof of P.
- Missing, delayed or contradictory evidence and the exact unresolved claim:
- Unimplemented live classes: invalid-origin certificate, direct DNS/QUIC/TCP22 bypass, mTLS, signature-trigger traffic and TLS1.3 client. These remain NOT IMPLEMENTED/NOT RUN, not implied coverage.

## Rollback / cleanup

- Closed-policy rollback approved/applied/effective evidence:
- CA/identity linkage removed only if separately approved; existing PKI resources untouched:
- Tunnel stopped; no OS trust change required:
- Dedicated lab removal approved and verified, remaining chargeable resources:
- Evidence retention/location/access and external leftovers:
