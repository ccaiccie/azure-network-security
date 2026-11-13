# Scenario12 validation status

Reviewed4November2026. This is a **source-complete all-Azure VPN simulation draft**, not a deployed or observed working hybrid network. No Azure resources, real guest services/security/routes, repository contents or actual VPN secrets were created/read/changed/transmitted by this work.

## Executed locally

- **94 local tests passed:**51 fixture/probe tests use only guarded loopback sockets and fake system commands;35 operator tests use fake Terraform/Azure CLI/local output JSON;8 small route-selection model tests illustrate documented prefix/source logic and are not Azure routing tests.
- **219 source assertions passed:** eight false gates, owned topology, reciprocal connection and secret-input boundaries, exact route/propagation/peering/policy/NSG source, private-management layout, cloud-init delivery, scoped ID guards, default-skipped connection reads and immutable evidence.
- Python AST6; Bash helper syntax5; service INI structure1; README Bash fences14 passed. The service explicitly permits AF_NETLINK for its startup `ip -j -4 addr` query while both capability sets stay empty. A regression checks that source contract; no systemd/seccomp/capability runtime test was performed.
- Source-level resource-reference scan found no dangling Azure resource names. This is not Terraform graph/type/schema validation.
- Compressed cloud-init source estimate **20,668 bytes**, including an8,192-byte structural reserve. It is **not an evaluated Terraform YAML/custom-data rendering**.
- Independent reviewer separately confirmed35 fake-CLI and8 route-model tests, checked routing/security/collector source and the AF_NETLINK/PSK-null fixes. Do not imply that review executed the entire94-test suite or live services.

Command logs: `syntax-checks.txt`, `source-checks.txt`, `local-tests.txt`. Machine-readable summary: `status.json`.

## Supplied but NOT RUN

- **17 Terraform plan-only mock-provider cases**. These cover disabled bootstrap, image/readiness gates, reciprocal connections, invalid/missing/off-stage PSK input, routing/NSG/management/policy contracts, invalid image IDs, stale connection readiness and the isolated connection-removal configuration. The removal mock does not prove an actual deletion transition from populated state. Public test sentinels are not generated or usable real credentials.
- Terraform/OpenTofu executable, initialized provider cache and HCL parser were absent. No installation/download/init was attempted; fmt/init/validate/test are **NOT RUN**. No real dependency lock was generated.
- AzureRM5.12.0 schema and Terraform grammar/type/graph evaluation remain unvalidated. Pinned gateway/connection documentation fetches cache-missed; readable current primary provider documentation was reviewed, not substituted as proof of pinned schema.
- Image compatibility, cloud-init/service startup, actual secure PSK input, gateway provisioning/crypto negotiation, non-BGP spoke propagation, effective routes, management, firewall enforcement/source preservation/logging, metric/diagnostic schemas and every positive/negative/stream/cleanup/cost outcome remain **NOT RUN**.
- Real branch S2S equipment, BGP, ExpressRoute/private peering/carrier service, FastPath, backup transport/failover and an externally owned state-free connection mode are **NOT IMPLEMENTED**.

## Safety and evidence limits

The operator supplies the matching PSK only for enabled connections. The input is rejected when connections are disabled, but sensitivity does not prevent persisted secret-bearing plans/state/backups. Workspace shared keys may also be in provider state. No secret is deliberately output by this lab. Raw state/plan/export/shared-key reads are excluded from helpers.

Connection GETs default to skipped; the explicit per-invocation response acknowledgment only enables projected reads of both verified owned connections. API receipt happens before client-side `--query`; sensitive response/metadata/error handling remains private. No actual PSK receipt or guaranteed omission is asserted. Missing/empty/null evidence never establishes health.

Timeout, Connected, HTTP200, a modeled route or local readiness alone is insufficient. Complete the worksheet with actual route, tuple, exact rule/log, listener and closure observations. GatewaySubnet restrictions and endpoint isolation before removing inspection routes are mandatory parts of the proposed operating procedure, not tested facts.

Teardown documentation explicitly requires verified isolation before clearing `connections_ready` together with `create_connections` and withdrawing PSK input to null. The separately reviewed connection-removal stage retains the closed gateway/firewall/route/management substrate. No runtime behavior changed.
