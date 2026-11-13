# Validation status

Last local review: 2026-11-04 UTC. Independent source draft only. No repository, cloud resource, authentication, FRR, nftables, routing/sysctl, capture or deployment actions were performed.

## Checks run locally

- Source-contract assertions covering isolated topology, actual computed service peers, scoped route propagation, absence of recursive/exact-prefix UDRs, original/restored NSG tuples, GRE outer wildcard-protocol disclosure, guarded inputs, strict control/transition/recovery behavior and compressed controller delivery.
- Safe Python fake-backend/control tests with external process/network calls blocked, loopback-only fixture/client tests and process-level fake Azure/Terraform collector tests. Local file locks and temporary files exercise serialization/uncertainty; they are not guest networking tests.
- Python AST, Bash syntax, basic systemd unit/drop-in INI structure and README Bash-fence parsing.

**Passed: 156 source assertions; 150 local tests (103 controller, 37 fixture/client, 10 mocked collector); 7 Python AST files; 7 Bash helpers; 3 unit/drop-in INI structures; 17 README Bash fences.** Final logs are recorded in status.json, source-checks.txt, syntax-checks.txt and local-tests.txt alongside this file. No count establishes FRR/nft grammar acceptance or runtime behavior. Mocked two-peer responses and JSON do not prove actual FRR default serialization, advertised-route schema, BGP convergence or Azure forwarding.

Regression scope includes partial peer updates, silently missing local export policy, ordinary state-write errors, transition markers, uncertainty and safe-close attempts, explicit reconciliation, per-peer empty advertised-route checks, independent bounded recovery, live-lock refusal, signals, foreign-node record rejection, strict config validation without assert reliance, and inner-versus-outer GRE input ordering. TCP tests retain attempted source port before connect, actual fixture SNAT peer/q, HTTP-not-sent after failed connect, stream completion and nonclobbering evidence.

## Supplied but NOT RUN

- Nine Terraform plan-only mocked-provider cases in tests/baseline.tftest.hcl. Terraform/OpenTofu, HCL parser, provider cache/binary and genuine lockfile are unavailable. No fmt, init, validate, test, provider schema or actual plan execution.
- Actual FRR10.4 installation/configuration parse, zebra import-check behavior, vtysh normalization, four real sessions, advertised paths or live reconciliation JSON.
- Actual nft syntax check, table application, sysctl, GRE interface/routes, kernel conntrack/SNAT, MTU/MSS, daemon/service/cloud-init execution or payload acceptance. Source-size checks are conservative estimates, not Terraform-rendered custom_data.
- Approved image contents/provenance, region/quota/capacity/pricing, SSH/Bastion and operator permissions.
- Any Azure resource deployment/read/change, effective route/NSG collection, metric query, packet capture, real application/NVA tunnel test, propagation/withdrawal/old-flow result, rollback or cleanup verification.

Known external prerequisite: a versioned approved image already containing the exact FRR family/version and all documented tools, with clean isolated guest routing/configuration and initially stopped FRR. No broad egress or package-install fallback is included.

This is a synthetic teaching NVA model, not vendor NGFW/state synchronization, encrypted GRE, production support, a real VM crash or seamless failover.
