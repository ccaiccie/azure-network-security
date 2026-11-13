# Scenario 15: layered Front Door and Application Gateway WAF

**Complete source draft with external certificate/DNS prerequisites, not a deployed or runtime-validated lab.** The owned topology is Front Door Premium → public Application Gateway WAF_v2 → controlled public App Service. It demonstrates three independent HTTPS connections and two WAF policies. It does not create a certificate, read a private key, provision a vendor service, implement Private Link, or prove high availability.

See [the full guide](../azure-15-layered-front-door-application-gateway-waf-guide.md), [runtime worksheet](RESULTS.template.md), [validation status](validation/STATUS.md), and [sources](SOURCES.md). No Azure authentication, deployment, certificate/secret operation, repository edit or push was performed while preparing this draft. All live actions below are future operator work requiring appropriate authorization. Boolean attestations and command flags do not obtain that authorization.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Future operator examples assume the lab/ working directory. Opening the package runs nothing.

## 1. Exact topology and ownership

The default new resource group is `inspection-waf`; region, globally unique edge endpoint and backend names are required inputs.

- `layered-frontdoor`: Premium_AzureFrontDoor with its allocated default `*.azurefd.net` hostname. `owned-https-route` uses HTTPS forwarding, HTTP-to-HTTPS edge redirect, no cache block, and an always-associated edge WAF policy. No custom edge domain is needed.
- `gateway`: VNet 10.60.0.0/16 with dedicated `appgateway` subnet 10.60.1.0/24. No unrelated workload, peering, UDR, forced default, firewall or hidden NIC route query is supplied.
- `regional-gateway`: WAF_v2, fixed capacity 2, static Standard IPv4 `gateway-public` P. This is a sizing choice, not a tested HA/failover guarantee. The named HTTPS listener `origin-https` requires SNI for the operator's `origin_fqdn`.
- The operator owns public DNS for Horigin and must point its A record exclusively to actual P. DNS records and the external zone are not Terraform-owned. Existing DNS values must be recorded and restored deliberately during cleanup.
- `waf-backend-plan` B1 Linux and the required new App Service `backend_name` provide Hbackend under `*.azurewebsites.net`. This is a public service protected by frontend access restrictions, not a private-IP backend. Its public default certificate terminates the third TLS leg; Node receives internal platform HTTP.
- `waf-observability` receives configured Front Door, gateway and App Service logs. No VM/Bastion is needed. Management is explicitly scoped Azure control-plane access and temporary C/32 SCM publication, independent of the gateway listener.

The external inputs are a versionless Key Vault certificate secret URI, an existing same-subscription user-assigned identity, public DNS control, and approved test-client public C/32. The module does not create identities, grants, vaults, certificate values or DNS records. The identity is attached to the gateway, which must already have the approved ability and network path to retrieve that certificate.

## 2. Certificate, trust and operational prerequisites

An existing software certificate must cover Horigin, have a valid publicly trusted full chain, and be Enabled, software-backed PFX with an exportable private key supported by Application Gateway Key Vault integration. Reference `https://VAULT.vault.azure.net/secrets/NAME` without a version, query or secret value. The operator owns renewal and rotation. The gateway runtime necessarily receives its private key; this source does not. Never substitute a secret data source, local PFX, password variable, custom-data certificate, or disabled certificate-name validation.

The existing user-assigned identity needs the approved Key Vault secret-read permission and vault network access. If either is absent, stop for the required security approval and prerequisite work. Do not broaden access or bypass the vault firewall. Merely supplying the URI or attaching an identity does not prove retrieval/rotation. The approved existing permission is Key Vault Secrets User under RBAC, or Secret Get under the vault-access-policy model. This module adds no Key Vault service endpoint, private endpoint, DNS link or firewall exception. A restricted vault requiring those changes is a blocker until separate network/access prerequisites are designed and approved; this new gateway VNet is not automatically connected to it. A Front Door-managed edge certificate cannot be exported to become this gateway listener certificate. Front Door requires a publicly trusted origin chain; disabling a name check would not make a self-signed chain acceptable.

Provide an approved subscription, new resource names, supported region/capacity, budget, current clock, and explicit permission for deployment, attaching the existing identity/certificate access, DNS changes, synthetic artifact upload/restart and probes. Use approved Terraform >=1.9,<2 and AzureRM 5.12.0, Python 3 with SSL and POSIX signal support, Node 24 for fixture checks, and current Azure CLI with Microsoft Entra deployment support. No package install, npm dependency or mutable container image is required. App Service's managed `24-lts` runtime can receive platform updates and is not bit-for-bit immutable; record the deployed runtime and source/package hash.

The external Python client uses an explicit reviewed public CA PEM bundle, default `/etc/ssl/certs/ca-certificates.crt`. `--ca-file` can select another approved public bundle. The exact bounded bytes are loaded via `cadata` and hashed; ambient `SSL_CERT_FILE`, `SSL_CERT_DIR` and extra system CA directories are not added. Approve the bundle's provenance: a strict certificate-verification setting alone cannot prove its roots are public/trustworthy. No `-k`, interception CA installation, authentication header, cookie or secret input is supported.

Terraform still is **not secret-free**: the provider can export App Service `site_credential` username/password and Log Analytics shared keys into state even with basic/local authentication disabled. Protect state, plans, CLI caches and evidence. Public references/tags can contain sensitive free text if misused; enter no secrets. CLI `--query` is client-side filtering, not proof that the full returned response contains no sensitive fields. Review private stderr and all retained metadata before sharing.

## 3. Traffic and security contract

The ledger is three separate client/proxy sessions:

1. C:c → selected Front Door edge:443, TLS for Hedge. Edge policy evaluates the HTTP request.
2. Observed Front Door backend egress E:e → P:443, TLS and Host/SNI for Horigin. E belongs to AzureFrontDoor.Backend, not the client or an NVA next hop.
3. Gateway public frontend P:g → resolved public App Service address B:443, TLS and Host/SNI for Hbackend. Public-backend source is P; do not label it an instance-private G address. B and ports are observed, not hard-coded. Node's internal socket or forwarded headers do not establish this public frontend source.

Responses follow each independent proxy connection in reverse. There is no backend route to C, original five-tuple preservation or shared conntrack claim. A private-backend alternative would have a different source/route contract and is not implemented.

`gateway-nsg` has these inbound rules, with required platform/default outbound access retained:

| Priority/name | Source → destination | Control |
|---|---|---|
| 100 frontdoor-backend-https | AzureFrontDoor.Backend → gateway subnet TCP443 | `gateway_ingress_enabled` |
| 110 approved-fdid-diagnostic | approved C/32 → gateway subnet TCP443 | separate diagnostic gate |
| 200 required-gateway-manager | GatewayManager → Any TCP65200–65535 | always Allow |
| 210 required-platform-probe | AzureLoadBalancer → Any | always Allow |
| 4000 deny-other-inbound | Any → Any | Deny |

This is the conventional public gateway architecture, not network-isolated Application Gateway. Do not copy VM-style outbound Deny or 0/0→None onto its subnet. Preserve documented platform operations and verify the service's current infrastructure requirements before deployment.

Backend main-site restrictions default Deny and include only P/32 when `backend_access_enabled`. SCM uses a separate unmatched Deny with only C/32 while `fixture_publish_enabled`; it does not inherit the main-site rules. FTP/WebDeploy basic publishing authentication is disabled. There is no operator-C main-site exception, public bootstrap Allow or service-tag-wide backend Allow.

## 4. WAF policy and diagnostic boundaries

Both policies are enabled and Prevention from creation. There is **no custom Allow** that short-circuits managed evaluation.

Edge `wafedgepolicy`:
- `BlockOtherSockets`, priority 10: Block when `SocketAddr` is outside C/32. This uses the connection identity rather than a user-supplied forwarded address.
- `BlockEdgeMarker`, priority 20: Block exact `X-Lab-Edge-Block: 1`.
- Microsoft_DefaultRuleSet 2.1, Block. Custom-marker success does not prove managed-signature coverage.

Regional `gateway-waf-policy`:
- `BlockMissingFDID`, priority 10: RequestHeaders selector X-Azure-FDID, negated `Any`.
- `BlockWrongFDID`, priority 20: negated anchored regex matching the exact profile resource GUID, with Lowercase transform.
- `BlockRegionalMarker`, priority 30: Block exact `X-Lab-Regional-Block: 1`.
- OWASP 3.2 managed policy with request-body checking. No redirects on the gateway bypass this policy.

The source tag includes other customers; FDID alone is forgeable. Both boundaries are necessary. Missing-header/duplicate normalization is not proven by source syntax. The lab requires live correct, missing, wrong, mixed duplicate, repeated-correct duplicate and case-variant observations. **If an ambiguous duplicate is accepted, do not set `fdid_negative_cases_verified` or publish the edge route.** Preserve the evidence and resolve the supported WAF handling separately. A 403 or timeout without the correct named rule/transaction is not that proof.

To distinguish WAF rejection from the NSG boundary, the module includes a deliberately temporary diagnostic exception for exactly C/32. It requires explicit `diagnostic_ingress_authorized`, healthy backend, verified DNS and closed edge/SCM gates. While it is open, the approved client can spoof the public FDID and reach the synthetic fixture. This weakens the normal source boundary for that client and must be authorized, closely supervised and closed promptly. It has **no automatic expiry**. The normal direct-P test is run with this exception closed and proves only network closure, not header-rule execution.

## 5. Gates and staged preparation

All 12 booleans default false: `deploy_lab`, `certificate_access_confirmed`, `origin_dns_verified`, `fixture_publish_enabled`, `fixture_ready`, `backend_access_enabled`, `backend_health_verified`, `gateway_ingress_enabled`, `fdid_diagnostic_ingress_enabled`, `diagnostic_ingress_authorized`, `fdid_negative_cases_verified`, `edge_route_enabled`.

Attestations are historical operator observations, not automatic reconciliation of live state. Revalidate after changed DNS, certificate, policy, profile GUID, source IP, artifact, backend settings or stale evidence. `fixture_ready` means the reviewed artifact's deployment was accepted; `backend_health_verified` separately requires observed /health success. This avoids treating unavailable HTTP access as artifact-deployment evidence. Changing `deploy_lab=false` after creation destroys the module, rather than pausing it.

1. Run local checks and review all source. In a separately authorized tool-preparation environment, initialize/pin the exact provider, run format/schema/mock checks and review the real plan. No lock file is fabricated.
2. Confirm certificate/identity/network access approvals. Deploy only substrate with `deploy_lab=true`, `certificate_access_confirmed=true`, all other gates false. The HTTPS listener exists, but NSG user ingress, edge route, main backend and SCM are closed.
3. Record actual P. Make the approved external DNS change Horigin→P and verify public resolution, certificate hostname/validity and gateway retrieval status without reading its secret. Then attest `origin_dns_verified=true`.
4. Keep edge and diagnostic ingress closed. Review/build the synthetic artifact, authorize code upload/restart, open only `fixture_publish_enabled`, publish the reviewed bytes, inspect actual deployment status, and close publication. Set `fixture_ready` only for the accepted reviewed artifact.
5. Open `backend_access_enabled` so only P/32 reaches the main site. Observe gateway custom HTTPS `/health`, expected host/status, and App Service frontend restriction logs. Attest `backend_health_verified` only after healthy evidence. An unhealthy backend can prevent WAF execution, so do not interpret diagnostic status as a WAF verdict before this stage.

Local and future provider checks, all distinct from deployment:
```bash
bash scripts/check-local.sh
# Future authorized provider preparation only; not run during drafting:
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```
Provider initialization can download software. Any apply/destroy, DNS or persistent-access operation needs separate approval and plan review; no such command is supplied.

## 6. Artifact publication and scoped evidence

From the approved operator environment, explicitly scope every read:
```bash
export SUBSCRIPTION_ID="REPLACE_WITH_APPROVED_UUID"
source scripts/common.sh
load_context
```
The guard validates deployment, all owned resource IDs/names, public hostnames/IPs, the existing identity's subscription, profile GUID and gate-map consistency. It disables dynamic extension installation. Install missing approved tooling through its authorized workflow, not as a silent read side effect.

Build locally, inspect both original files and the archive, record the hash, then obtain the required upload/restart authorization. The helper never rebuilds at upload time:
```bash
python3 scripts/build-origin.py
python3 -m zipfile -l build/origin.zip
sha256sum build/origin.zip
# Only after explicit authorization and the separate SCM gate is open:
: "${REVIEWED_SHA256:?Set the independently reviewed ZIP SHA256}"
bash scripts/deploy-origin.sh --confirm-synthetic-origin-upload \
  build/origin.zip "$REVIEWED_SHA256"
```
The publisher verifies hash and structure on the same bytes, writes a private snapshot and uploads that snapshot through Entra-capable Azure CLI. It does not fetch publishing credentials or enable basic auth. A nonzero/uncertain deployment outcome is not retried automatically; inspect deployment status before deciding. Close SCM again before diagnostic or edge activation.

Create a new six-field public configuration and fresh evidence directory:
```bash
RUN=$(mktemp -d)
chmod 700 "$RUN"
bash scripts/make-probe-config.sh "$RUN/probe-config.json"
bash scripts/collect-control-plane.sh "$RUN/control"
```
The final output paths must not exist, even as empty directories, and must have no symlink ancestor. Collector receipts include declared outputs, start/completion UTC, projected configuration/backend health, per-read exit/stderr and `PRIVATE-HANDLING-REQUIRED.txt`. It never queries a Key Vault value, app setting, publishing credential, hidden gateway/App Service NIC, Terraform state or plan. Empty/failed reads remain inconclusive; configuration is not request-path proof.

## 7. Diagnostic FDID acceptance, then public edge demonstration

Every probe is a fresh bounded IPv4 HTTPS GET to `/probe/<new UUID>`, with `azure-waf-lab/<UUID>` User-Agent. It validates the real service hostname/certificate using the approved CA bundle. No proxy, redirect, retry, cookies, authorization or TLS bypass is used. At most 20 seconds overall and 5 seconds per socket operation; response body limited to 8,192 bytes and retained only as hash/length. No exploit payload is used.

First authorize/open the diagnostic C/32 gate while edge/SCM remain closed. Run one correct-header request and collect actual gateway/backend evidence:
```bash
scripts/waf-probe --config "$RUN/probe-config.json" --mode fdid-correct \
  --confirm-diagnostic-ingress --out "$RUN/first-diagnostic"
```
Close diagnostic ingress immediately after this first positive. Wait for the change to become effective, use a new baseline `direct-gateway` probe to confirm the client can no longer reach the fixture, and review TLS, policy, backend, source and response evidence. An interrupted client or failed control update does not close the persistent gate automatically.

Only then separately authorize/reopen diagnostic ingress for the full matrix:
```bash
DIAG=$(mktemp -d)
for mode in fdid-correct fdid-missing fdid-wrong fdid-duplicate fdid-duplicate-valid fdid-case; do
  if scripts/waf-probe --config "$RUN/probe-config.json" --mode "$mode" \
    --confirm-diagnostic-ingress --out "$DIAG/$mode"; then
    printf '%s: response captured; inspect named rule and fixture evidence\n' "$mode"
  else
    printf '%s: incomplete or failed observation; inspect result.json\n' "$mode"
  fi
done
```
Expected correct/case-normalized controls return exact fixture JSON and case. Missing/wrong/duplicate controls must be blocked with matching regional WAF evidence and healthy backend. The helper's exit code is not a policy verdict. If unexpected behavior, late logs or missing fields remain, keep edge closed. After the matrix, close diagnostic ingress, verify new direct-P closure, review every case, then set `fdid_negative_cases_verified=true` only if acceptance requirements passed.

Enable `gateway_ingress_enabled` for the Front Door source tag and inspect origin HTTPS/HEAD `/health` configuration and any available probe evidence. A disabled/no-traffic route may not yield enough Front Door observations; absence is unverified, not a guaranteed pre-publication health pass. After header-case acceptance, diagnostic closure and backend readiness, the first controlled C/32 edge request is the full-path test. Enable `edge_route_enabled` only for that approved stage. A Front Door all-unhealthy condition still can send traffic and is never a closure gate. The edge route itself must stay disabled until release is approved.

Run a single first `edge-positive`, then close the edge route and review all three TLS/proxy/WAF/backend records before separately reopening for broader tests. With diagnostic and SCM gates closed, the matrix is:
```bash
EDGE=$(mktemp -d)
for mode in edge-positive edge-block regional-block direct-gateway direct-backend; do
  if scripts/waf-probe --config "$RUN/probe-config.json" --mode "$mode" --out "$EDGE/$mode"; then
    printf '%s: observation captured, not automatic PASS\n' "$mode"
  else
    printf '%s: inspect failure stage and independent evidence\n' "$mode"
  fi
done
```
- `edge-positive`: exact marker, message and case JSON, plus correlated edge/gateway/backend evidence.
- `edge-block`: named BlockEdgeMarker at edge. Lack of downstream logs alone does not prove no forwarding.
- `regional-block`: named BlockRegionalMarker with healthy backend, after ordinary edge checks. A managed edge block instead is a different result.
- `direct-gateway`: sends correct forged FDID to P with correct origin Host/SNI, but the closed C/32 NSG exception must prevent fixture access. This does not test the FDID rule.
- `direct-backend`: must fail the App Service P/32 restriction; use frontend audit evidence, not a Node response alone.

`attempt.json` retains the bound source port and attempted destination before connect. A default wildcard local address is not the selected interface or public NAT C. Supply approved `--local-address` for an exact local bind; `connected_local` is recorded after successful connect. Actual public C and proxy addresses need service observations. `result.json` includes UTC start/end, stage, TLS peer certificate hash and safe response fields. `waf_block_proven`, `origin_header_protection_proven` and `three_tls_legs_proven` remain false for operator assessment, even on exact fixture content.

## 8. Evidence and limits

Use the bounded KQL templates in `queries/` only after substituting exact guarded IDs, actual UTC intervals and case UUIDs. They do not auto-query or export secrets. Front Door categories use AzureDiagnostics here; gateway uses AGWAccessLogs/AGWFirewallLogs; backend uses AppServiceHTTPLogs/ConsoleLogs and AppServiceIPSecAuditLogs. Actual category/table/field availability remains runtime-unverified. Missing `column_ifexists` values must not be interpreted as successful evidence.

Correlate case path/User-Agent and X-Azure-Ref with edge records, gateway TransactionId/rule/action/host and backend evidence. Retain gateway backend TLS protocol/source-port observations if available; do not invent hidden packet captures. AppServiceIPSecAuditLogs provides frontend CIp/Result/host observations, without promising a case-ID field. Node's safe JSON attribution headers are observations, not authenticated client identity. X-Azure-ClientIP, X-Azure-SocketIP, forwarded lists and immediate socket addresses are not interchangeable.

A custom Block demonstrates only that custom rule, not managed exploit coverage. A fixture response proves content reachability, not all three TLS legs or WAF enforcement by itself. Failure from certificate, DNS, unhealthy origin/backend, closed NSG or App Service restrictions is not a WAF denial. Wrong-certificate/health-path changes are conceptual troubleshooting controls, not implemented mutation switches. Front Door Premium→Application Gateway Private Link is currently supported, but requires separate source/approval/public-exposure treatment and is **not implemented here**. IPv6, HTTP/2, WebSocket/stream/HA and client-auth workflows are outside this bounded lab.

## 9. Close, rollback and cleanup

Stop/finish finite test clients. First disable `edge_route_enabled`; retain WAFs, certificate verification, FDID rules and source restrictions. Confirm updated configuration and fresh edge closure, accounting for global propagation and in-flight requests. Never use unhealthy probes or a successful control-plane response as immediate closure proof.

Close `fdid_diagnostic_ingress_enabled` and `fixture_publish_enabled`, verify both exceptions are gone, then disable `gateway_ingress_enabled` and verify new direct/edge data access is closed. Before closing backend access, set `backend_health_verified=false` as well as `backend_access_enabled=false`; the gateway/diagnostic gates must already be false or validation correctly rejects the transition. Preserve mandatory platform outbound/control rules. Keep `fixture_ready` only as a historical artifact record, or clear it once backend access is closed.

For rollback, restore only reviewed source/configuration and repeat relevant DNS/TLS/health/header evidence. Never remove a WAF, open broad ingress, enable backend public bootstrap, disable certificate checks or weaken identity access to recover. Any C/profile/P/certificate/fixture change invalidates affected acceptance evidence; close user paths first.

After verified isolation, review a destruction plan for all owned resources and reset dependent gates consistently. Remove only the owned origin DNS record change, with explicit restoration of preexisting values; preserve the external vault/certificate/domain and shared identity. Revoke only the specifically approved certificate access when the gateway no longer needs it, under the appropriate security approval. No delete/purge or destroy command is supplied. Confirm cost-bearing leftovers and evidence retention; `deploy_lab=false` means destruction, not suspension.

Costs include continuous Front Door Premium base/WAF/requests, WAF_v2 capacity, Standard public IP, B1 App Service, logs, data transfer and external domain/certificate/Key Vault usage. Gates and closed routes do not stop these charges. Use current region/subscription pricing before approval. No live quote, deployment-duration promise or zero-cost idle claim is made.
