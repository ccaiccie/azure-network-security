# Validation status — 4 November 2026

Source draft only. No Azure resource, authentication, guest security, route, packet inspection, deployment, apply or destruction action was performed.

## Executed locally

- Python AST and Bash syntax checks, service INI structure and README Bash-fence parsing.
- Source invariants, including bracket balance/text assertions, fixed topology/rules/gates, cloud-init source delivery and a conservative 42,576-byte base64 payload plus metadata estimate. This is not Terraform rendering, an HCL parser or schema validation.
- Fixture/probe tests: real sockets guarded to loopback only; all ip/systemd subprocesses mocked or prohibited. These validate local protocol/evidence mechanics, not the Azure image, systemd hardening or actual private IPs.
- Operator collector tests: fake Terraform output and fake Azure CLI only; explicit subscription/ID guards, closed deployment, missing approved extensions, nonclobber, per-command failures, optional unverified Firewall-route token and empty-result caution. No Azure requests were made.
- Exact counts and command logs: `syntax-checks.txt`, `source-checks.txt`, `local-tests.txt`, `fixture-tests.txt` and `status.json`.

## NOT RUN / unresolved

- Terraform/OpenTofu executable and initialized provider cache are absent. No software installed, provider download or init attempted. `fmt`, `init -backend=false`, `validate` and the **10 supplied plan-only mock-provider tests** remain NOT RUN. `.terraform.lock.hcl` is intentionally absent.
- Exact AzureRM 5.12.0 executable/schema compatibility, resource plan graph, computed connection drift, rendered cloud-init and API acceptance are unverified. Current official provider docs were reviewed; several direct pinned-document fetches failed. No claim of provider validation is made.
- Azure subscription/provider registration/permission/quota/region capacity, all resources, Bastion/native CLI behavior, image/cloud-init/systemd, actual listeners/private fixtures, route selection, private intent convergence, original tuple at B, named logs/ingestion, Firewall session revocation, NSG existing-flow closure, billing and cleanup are NOT RUN.
- Firewall effective-route API type token is not established from primary CLI schema. Collector defaults to a required manual portal evidence item. Any optional candidate read is explicitly unverified; an empty success is not route proof.
- Local AST/INI/bracket tests do not prove HCL grammar, provider schema, systemd unit semantics, actual network behavior or security adequacy. Mocks cannot prove API behavior or managed-platform state.

The lab is complete as a source draft with an operator runbook, not ready-to-claim successful infrastructure or inspection. Populate RESULTS.template.md only with real separately authorized observations.
