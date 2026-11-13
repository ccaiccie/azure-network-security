# Scenario 14 validation status

Reviewed locally on 4 November 2026. This is a complete source draft, not a deployed or runtime-validated Azure lab.

## Checks completed

- **88 local tests passed:** 52 fully mocked guest-helper tests, 28 fake-CLI operator tests and 8 pure route-policy model tests.
- **144 source assertions passed.** These check selected strings, relationships, source references, fixed payload bytes/hash, delimiter balance and conservative compressed-source size. They are not an HCL parser, provider schema validator or Azure route engine.
- Python AST parsing passed for 5 files. Bash syntax checks passed for 5 helpers and 9 README Bash fences. No systemd service is supplied or executed.
- The estimated compressed source plus an 8,192-byte reserve is 15,640 bytes. This is not Terraform-rendered custom-data; its actual rendered size and cloud-init operation remain unverified.
- Local receipts: [syntax](syntax-checks.txt), [source assertions](source-checks.txt), [test output](local-tests.txt).

The helper suite denies real socket, DNS, HTTP, TLS and subprocess operations and substitutes explicit fakes. Its token strings and certificate bytes are conspicuous, unusable test sentinels. Mocked TLS verifies configuration and control flow only, not real certificate parsing, trust, hostname, expiry, revocation or handshakes. Fake Azure/Terraform commands test argument scoping and evidence handling, not actual APIs. Route-model tests express the documented scenario assumptions, not observed platform behavior.

## Not run or established

- Terraform `fmt`, initialization, `validate` and `test`: **NOT RUN**, executable and initialized provider cache absent. No provider was downloaded or installed. No HCL parser or loaded provider schema was available.
- **17 mock-provider plan-only cases are supplied but NOT RUN.** They are not included in the 88 executed tests.
- AzureRM 5.12.0 documentation/source was inspected for selected resources. The pinned subnet and policy-rule documentation fetches were unavailable, so current official documentation informed those fields. This does not establish compatibility of the full module. No lock file is fabricated.
- Azure authentication, resource creation/change, managed identity/RBAC creation, token acquisition, Blob upload/read, actual DNS/TLS, PE approval, NSG enforcement, effective routes, Firewall/application logs and service logs: **NOT RUN**.
- Provider state/plan handling, actual custom-data rendering, image prerequisites, private management, costs, role propagation/revocation and cleanup/retention: **NOT RUNTIME-VERIFIED**.

No cloud or guest/kernel operation, secret generation/read/transmission, Terraform apply, repository edit or push was performed. A future deployment creates persistent identity/access and requires the operator's explicit approval. Terraform state may include provider-exported Storage and Log Analytics keys even while those authentication paths are disabled. Keep future state, plans, outputs and evidence private.

Use [the runtime worksheet](../RESULTS.template.md) for future authorized observations. A 403 establishes neither authorized Blob access nor inspection; a 200/content match needs separate route and Firewall evidence. Do not populate runtime results from these local checks.
