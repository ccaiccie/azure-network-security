# Scenario 14 runtime evidence worksheet

**Every Azure/provider/TLS/token/Blob result below is NOT RUN.** Local mocked tests are recorded separately in validation/STATUS.md and cannot fill these cells. Keep evidence private; never include an access token, Authorization header, account/workspace key, SAS, raw IMDS response or real customer data.

Record approved subscription/RG/region/account/image version, source/provider-lock hashes, authorization references for resource/identity/RBAC/data operations, all gates, PE flags and actual F/E. Record start/end UTC, private evidence directory and exact case UUID. The expected proof object is51 bytes with SHA256003da15a8a946410c90f1216eb109b19e40ba6b307fee105d277cb43cc07e8e0.

| Required observation | Status | Private reference |
|---|---|---|
| Provider fmt/schema/mock plans and actual rendered custom-data | NOT RUN | |
| Approved region/PE NSG support/quota/cost/image/public CA/time | NOT RUN | |
| Actual resources and independent reader/seed private management | NOT RUN | |
| Two distinct system identities; no competing broad/writer grant on reader | NOT RUN | |
| PE Approved, exact owned account/blob subresource/E allocation | NOT RUN | |
| Both PE network policies Enabled and exact source-subnet NSG | NOT RUN | |
| Actual reader and seed E/32→F with direct peering competitor | NOT RUN | |
| F onward endpoint route, no recursive Firewall E/32 UDR | NOT RUN | |
| Ordinary Blob CNAME/A/TTL, hub private link/zone group, OS/F consistency | NOT RUN | |
| Closed reader collection fresh named Deny with healthy DNS/NSGs | NOT RUN | |
| First noauth strict TLS/service response and matching Firewall Allow | NOT RUN | |
| First reachability closed/reviewed before further activation | NOT RUN | |
| Authorized seed container Contributor, seed-only path and identity | NOT RUN | |
| Fixed create-only PUT201 and matching service request evidence | NOT RUN | |
| Seed requests finished, app/443 closed and writer role removal verified | NOT RUN | |
| Authorized reader container Reader role and correct principal | NOT RUN | |
| Reader200 plus exact51-byte content/hash | NOT RUN | |
| Noauth auth-negative under same healthy network Allow | NOT RUN | |
| Restored named reader Deny on a fresh noauth flow | NOT RUN | |
| Stopped sessions, all Blob envelopes/Allows closed before route changes | NOT RUN | |
| Optional isolated route/policy configuration observations, no live bypass request | NOT RUN | |
| Restored Enabled/E32/DNS/route evidence before any reopening | NOT RUN | |
| Final role/resource cleanup and cost-bearing leftovers/retention review | NOT RUN | |

Per-case record: mode/role; attempted_local and attempted_destination from attempt.json; start/completion UTC; TCP/TLS/request status; ordinary hostname/certificate hash; sanitized service headers/status; expected/received content hash and length; authorization operation reference; matching AZFWApplicationRule source tuple/FQDN/action/collection/rule; matching StorageBlobLogs ClientRequestId/status/authentication/requester/caller observation; missing evidence and conclusion.

403 does not establish data access, private routing or inspection.200 with exact content establishes authenticated data access only when the credentialed request/service evidence agree; correlate route/Firewall evidence separately.201 means the create request was accepted, not that a later independent read/hash has passed. A failed or interrupted PUT can have an uncertain service outcome. Do not overwrite/retry/delete automatically after409/412/timeout. A blocked pre-HTTP flow has no service case-header receipt. Empty logs, stale routes, unsupported views, role-propagation delay and missing/null fields are inconclusive, not passes. Role removal does not promise immediate invalidation of all issued tokens.
