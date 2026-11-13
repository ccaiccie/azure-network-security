# Validation status: 4 November 2026

## Passed locally

- 164 tests:61 guarded-loopback/socket-mock fixture/probe tests,70 fully mocked controller tests,25 fake Terraform/Azure CLI operator tests,8 pure longest-prefix route-model cases.
-126 source contract assertions, including balanced-delimiter smoke checks, exact resource/gate/route/policy/NSG/fixture paths, management separation and compressed-source budget.
- Python AST:8 files; Bash syntax:7 helpers and14 README fences; INI structure:2 service files. These are not systemd semantic/startup checks.
- Compressed source aggregate plus8192-byte reserve:32836bytes. This is an estimate, not Terraform-rendered custom-data.
- Operator regressions cover strict subscription/RG/resource identity maps, missing/null/foreign IDs, canonical IPs, source-mode mismatch, private nonclobbering output, retained failures and no runtime verdict from empty reads.
- Controller tests execute actual Python ownership/state/policy code against a command simulator. They cover unowned rejection, closed boot/prepare, source-selected SNAT,8082 drop, acknowledgments, normal bounded restoration, signal handling, locks, drift, state/event/marker failures, finalization and capture errors. All commands/sockets are mocked or blocked.
- Fixture tests use only guarded loopback sockets and mocked system commands. No public test address was contacted. Case/bound tuple/time persistence and evidence collision safeguards are tested locally.

The finalization failure test deliberately shows the limitation: after a final stable-state rename/fsync failure and every recovery write failing, surviving files may look stable. The command still fails and reports uncertain. No multi-file atomicity or disk-failure recovery guarantee is claimed.

## Supplied but NOT RUN

-12 Terraform mock-provider plan-only cases in tests/baseline.tftest.hcl.
- terraform fmt/init/validate/test: executable absent, provider cache absent, no provider lock or schema available. No installation/download attempted. Direct pinned AzureRM5.12 Firewall documentation fetch returned cache miss; current official docs do not substitute for pinned schema validation.
- Actual Terraform-rendered custom-data, resource graph/provider API validation, deployment and region/quotas/cost verification.
- Image capabilities, conntrack sysctl clean-boot availability, nft syntax/kernel transactions, systemd sandbox startup, cloud-init, sysctl application/restoration, actual conntrack/NAT/capture behavior.
- Azure Firewall management/data operation, F/S allocation, Standard public-IP mappings P/D, SDN routes/NSGs, Bastion access, logging, real positive/negative flows and failure/cleanup behavior.
- VPN/IPsec/Default Site/BGP/ExpressRoute/FastPath: not implemented and not tested, rather than merely unrun optional flags.

No cloud authentication/API/resource change, repository operation, secret generation/read/transmission, real guest/kernel command, actual capture or deployment was performed. Existing public-looking values in tests are synthetic fixtures guarded from external I/O. Local results do not establish that Azure deployment or a live forwarding path will work.

Records: syntax-checks.txt, source-checks.txt and local-tests.txt. Re-run check-local.sh after any source edit and preserve separate authorized runtime evidence using RESULTS.template.md.
