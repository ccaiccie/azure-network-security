# Scenario 15 validation status

Reviewed locally on 4 November 2026. This is a complete source draft with external certificate, identity/access and public-DNS prerequisites. It is not a deployed, schema-validated or runtime-validated lab.

## Completed local checks

- **59 Python tests passed:** 31 fully mocked probe tests and 28 fake-CLI operator/publisher tests.
- **13 Node fixture contract groups passed.** They invoke the handler with fake requests/responses; no HTTP server or socket is started.
- **147 selected source assertions passed:** gate defaults/relationships, scoped resources, TLS/FDID/WAF controls, no custom Allow, mandatory NSG dependency ordering, reference-only certificate integration, helper guards, selected excluded resources, reference consistency and delimiter checks.
- Python AST parsing passed for 5 files; Bash syntax passed for 6 helpers and 7 README Bash fences. `node --check` passed for the fixture.
- Local receipts: [syntax](syntax-checks.txt), [source assertions](source-checks.txt), [Python tests](local-tests.txt), [Node contracts](node-tests.txt).

Mocked probe tests deny real socket, DNS, HTTP, TLS and subprocess surfaces. Their public-CA/certificate strings are intentionally invalid sentinels, not generated credentials or certificates. These tests check explicit trust-input/control-flow behavior, not real certificate parsing, public-root provenance, hostname/expiry/revocation validation or a handshake. Fake Azure/Terraform scripts exercise scoping, nonclobbering evidence and reviewed-package upload arguments without contacting services. A successful fake upload is not a real code deployment.

Source assertions are not a HCL parser, Terraform graph evaluator, provider schema loader or service rule engine. They cannot establish missing/duplicate FDID semantics. Runtime ambiguous duplicate acceptance remains a release blocker regardless of these passing checks.

## Not run or established

- Terraform `fmt`, initialization, `validate` and `test`: **NOT RUN**, executable and initialized provider cache absent. No provider installation/download or lock-file generation was performed.
- **16 mock-provider plan-only cases are supplied but NOT RUN.** These are separate from the 59 executed Python tests.
- Pinned AzureRM 5.12.0 Web App, workspace and diagnostic documentation was reviewed. Pinned gateway/WAF/route fetches were unavailable; current official docs informed those resources. Full pinned-provider compatibility remains unvalidated.
- All Azure authentication, provisioning, identity/certificate access, secret retrieval, DNS change, artifact publication, TLS/WAF probes, backend health, log delivery/correlation and cleanup: **NOT RUN**.
- Real public-CA trust, Front Door header normalization, public-backend source P, App Service frontend restrictions, all three TLS/proxy associations, global closure propagation, capacity/cost and HA: **NOT VERIFIED**.

No Terraform apply, cloud/repository mutation, real secret/key/certificate generation or retrieval, or live endpoint request was made. Future source deployment attaches an existing identity and uses its approved Key Vault permission; required approvals are not obtained merely by setting gates.

No certificate value or password input is included, but future Terraform state can contain provider-exported App Service credentials and Log Analytics shared keys. Keep state, plans, outputs, CLI stderr and logs private. CLI projection limits retained fields client-side; it is not a guarantee about full response receipt.

Use the [runtime worksheet](../RESULTS.template.md) for separately authorized live observations. Do not convert mock results, a 403/timeout, a healthy probe or an exact response body into unsupported WAF/path claims.
