# Validation status:4 November2026

This is an Azure/Linux teaching **source draft**, not an observed successful deployment, vendor NGFW, stateful firewall or production HA solution. No cloud resources, guest kernel/network/service settings, repository contents, credentials, package installations or actual packet captures were changed by this work.

## Executed locally

- Combined suite:85 tests passed.41 controller tests use fully mocked ip/nft/process/state behavior,30 fixture/probe tests restrict real sockets to guarded loopback and prohibit DNS/actual system commands,14 operator tests use fake Terraform/Azure CLI and local JSON only.
- Python AST7, shell syntax8, service INI structure5 and README Bash fences17 passed. Service INI parsing is not systemd semantic or capability validation.
-208 source assertions, including fixed addresses/gates, Gateway nonfloating rules, exact VXLAN pairs, independent probes, NSGs, management-only peering, no UDR/NAT/outbound bypass resource, declared ID guards, actual bridge-family policy source and private evidence handling.
- Gzip round-trip/source estimates with8KiB metadata reserve:NVA24008bytes,app16044bytes. These are conservative source estimates, **not Terraform-rendered custom-data** or cloud-init execution.
- Independent review hardened transition bookkeeping/storage failures, emergency-close uncertainty, precise named primary drops, no-DNS health startup, source tuple capture, collision handling, checkout-relative external launcher resolution and late-finalization storage failure. Pending removal is last fallible success bookkeeping; final snapshots/events are pre-finalization and require subsequent status/health verification. Marker survival cannot be guaranteed after unlink/fsync and failed rewrites. Tests are evidence of those mocked branches only.

Exact machine-readable summary is in status.json; command logs are syntax-checks.txt,source-checks.txt,local-tests.txt.

## Supplied but NOT RUN

-12 Terraform plan-only mock-provider cases, covering closed bootstrap, prerequisite gates, tunnel/rule/probe/NSG contracts, chain activation and invalid inputs.
- Terraform/OpenTofu executable, initialized provider cache and HCL parser are absent. No installation/provider download was attempted. fmt/init/validate/test are NOT RUN; no genuine provider lock file exists.
- AzureRM5.12.0 schema, HCL grammar/type/graph evaluation, Gateway eligibility, API acceptance and no-healthy backend behavior are unvalidated. Current primary docs and source were reviewed; direct pinned-provider source fetches were unavailable to this worker.
- Real nft parsing/atomic transactions, iproute2 JSON, kernel bridge/VXLAN/FDB behavior, image/systemd/capability/cloud-init execution and MTUs are NOT RUN. iproute2 JSON source review is not actual guest verification.
- Actual C/P addresses, public exposure, cloud routing/NSGs, Bastion access, NVA outer envelope, consumer translation boundary, probe convergence, payload/PMTU behavior, same-instance return, policy negatives, old/new flow behavior and cleanup/billing are NOT RUN.

## Evidence limitations

The stateless C↔{P,B}:8080 envelope is a proposed bounded investigation policy. It does not prove where consumer translation occurs. Decode actual outer/inner captures and correlate backend/client evidence before filling the results worksheet. A named rule source, HTTP200, local health or fixture marker alone is not inspection proof.

Declared outputs/tags/diagnostics and bounded PCAP/body evidence can contain sensitive data. CLI --query is client-side, not a secrecy boundary. Keep evidence private and review/redact an approved copy before sharing; no general redaction or automatic upload is provided.

All optional/out-of-scope variants and vendor features remain unimplemented as documented in README. Future runtime actions require their own approval and prerequisite review; none were performed here.

README first-observation sequence was tightened on4November2026: finite positive/capture only, close both NVAs and review actual tuples, then separately reopen for broader controls. The full85-test/208-assertion suite was rerun successfully after this documentation change. No runtime actions occurred.
