# Validation scope

Checked 4 November 2026. **Draft only: no Azure deployment or Terraform/provider validation.**

## Passed locally

- `bash -n` for all four shell scripts.
- 42 focused source-contract checks covering intact comparison operators, provider pin/registration, topology/peering, private subnets, route switches, named firewall decisions, scoped NSGs, no workload public IP/public egress Allow, fixture startup declarations and diagnostics.
- Seventeen local Python tests: real fixed-response fixtures on **loopback only** at TCP8080/8081 and an ephemeral loopback port, source/port/role JSON identity, no file serving, long-path/POST rejection, readiness helper with real loopback requests plus mocked service/socket commands, probe behavior for both A/B and optional A/C with fake curl/network tools, and baseline/C evidence collection with fake Azure/Terraform commands.
- All local fixture servers were shut down after tests. Synthetic loopback observations are not evidence of Azure listener readiness or private routing.
- Seven provider-mocked plan-only test runs are supplied for exact baseline route/NSG/firewall tuples, default-only and blackhole flags, C topology and /24 routes, return-route removal, and unpinned-image rejection. These Terraform tests were **not executed**, and are not counted among passing local tests.
- Manual source/dependency review against official documentation. No custom text formatter was used to rewrite comparison expressions.

Full output: `local-checks.txt`. Machine-readable summary: `report.json`.

## Blocked / not run

- `systemd-analyze verify fixtures/azure-ew-fixture@.service` could not initialize because the executor's `/run/systemd` is read-only. The unit has **not** been verified by systemd or loaded/started here. Exact output: `systemd-unit-check.txt`.
- Terraform/OpenTofu are unavailable. Terraform fmt, provider initialization, validate and optional mocked plan tests were **not run**. No provider package was downloaded and no lock file was invented. Source checks are not an HCL parser.
- No Azure login, subscription/region/quota check, provider registration, deployment plan/apply/destroy, Bastion access, cloud-init boot test, actual VM listener check, Azure route query, packet capture or firewall/KQL test occurred.
- No repository was edited, committed or pushed. No cloud resource was created, changed or deleted.

## Before declaring success

1. Run formatting, approved pinned-provider initialization, Terraform validation and supplied mocked tests. Retain/review a genuine provider lock file and select a concrete approved image version.
2. Verify subscription/region/permissions/policy/capacity/pricing and approve the actual deployment plan.
3. Confirm boot/cloud-init and the owned systemd services. Run `ew-ready` on **all enabled** real VMs, proving A:8080, B:8080/8081 and optional C:8080/8081 before negative probes.
4. Capture actual routes/NSGs/peerings, source-visible positive response, both named firewall negatives and the positive retest. Use `RESULTS.template.md`; skipped/incomplete tests are not passes.
5. If running optional route experiments, separately authorize them and verify full baseline rollback. The optional same-VNet C variant is implemented but unvalidated by Terraform or Azure; separately verify its /24 routes, three named rule decisions, positive retest and rollback. Enabling/disabling C can replace existing A/B VMs because cloud-init changes.
6. Obtain deletion approval and independently verify removal of the dedicated billable lab resources.
