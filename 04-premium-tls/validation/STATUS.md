# Validation status, 2026-11-04

## Completed locally

- Seven Bash helper files parsed with `bash -n`.
- Ten README Bash command fences parsed without execution.
- Python helper/test source parsed with Python AST; Node fixture syntax checked.
- 82 focused source assertions passed: gates, exact policy/rule/route/NSG wiring, identity/CA references, no secret/data/access-grant resources, Bastion, origin restrictions, trust isolation and explicit subscription.
- Ten Node tests passed against **127.0.0.1 HTTP only**: allowed/blocked/health200 and identity, exact-path rejection, method/header checks and explicitly untrusted forwarded observations.
- 26 Python helper tests passed with **fake curl, OpenSSL, Azure CLI and Terraform**: trust flags, separate chain capture, failure retention, source guard, exact paths, public-material rejection, refusal before unapproved upload, case-matched User-Agent, subscription scoping, required reviewed ZIP hash and rejection of upload drift. A successful upload test uses a fake Azure CLI only. **Mocked OpenSSL does not validate real certificate parsing, expiry, hostname/chain trust or pinning.** Those remain untested.
- Original Node fixture ZIP was built locally and deterministic contents/checksum checked. It was never uploaded. No CA/certificate/key was generated; mock PEM text is non-cryptographic dummy text consumed only by fake OpenSSL and deleted with test temp files.
- Official current Microsoft documentation and official HashiCorp provider source reviewed. Some versioned firewall doc URLs were unavailable; main-branch source was reviewed instead and is not a substitute for the pinned provider schema.

See `local-checks.txt` for the actual local run. Local test logs contain only synthetic loopback/mock data. These checks do not parse HCL or execute provider logic.

## Supplied but NOT RUN

Eleven Terraform **plan-only mock** runs in `tests/baseline.tftest.hcl`: root disabled, closed infrastructure, CA-only closed gate, ready policy, and seven invalid-input cases. These require Terraform and the real provider schema and have not been executed. No mock apply run is supplied.

## NOT RUN / unavailable

- Terraform and OpenTofu executables are absent; HCL parser unavailable.
- `terraform fmt`, `init -backend=false`, `validate`, mock test plans, real plan and provider schema checks were not run. No lockfile was generated. Formatting has not been certified by Terraform.
- No Azure login/CLI/network call to a tenant; no provider registration, upload, resource creation/change/deletion, secret read, access grant or apply.
- No Key Vault retrieval, CA linkage, certificate validation against a real server, TLS inspection, App Service deployment/runtime, Bastion session, effective Azure route/NSG or diagnostic ingestion check.
- Region/quota/capacity, deployment completeness, provider API compatibility and actual resource costs are unverified.

The source is an executable **draft with explicit prerequisites and future operator steps**, not a demonstrated successful deployment. Never convert local mock passes into Azure runtime claims.
