# Validation status

Checked 4 November 2026. This is a **draft, not a deployed or provider-validated lab**.

## Passed locally

- `bash -n` for `scripts/check-local.sh`, `scripts/collect-control-plane.sh` and `scripts/guest-tests.sh`.
- 30 focused source-contract checks: fixed address layout, computed firewall next hop, private workload subnet, DNS proxy, mutually exclusive policy modes, peering flags, absence of public VM IP/DNAT/NAT Gateway/private-key generation, SSH and log settings, plus intact comparison operators across all eight HCL/example/test files.
- Five guest-harness tests with fake local `curl`, DNS and network tools: network observations; application-mode reporting; rejecting the wrong machine; rejecting an unapproved positive hostname; and explicitly marking DNS bypass tests NOT RUN when dig is absent. **No network requests are made by these unit tests.** Their documentation IPs and responses are synthetic.
- Manual comparison against current official HashiCorp AzureRM and Microsoft Azure documentation; source links and fetch/version limitations are in `SOURCES.md`.
- Manual dependency review: firewall does not depend on spoke; spoke DNS references computed firewall private IP; VM waits for workload NSG/route association, peering and diagnostics; no managed firewall subnet NSG/default-to-self UDR.

Full local command output: `local-checks.txt`.

## Not run

- `terraform fmt`: Terraform and OpenTofu executables are not installed in this executor. A readability-alignment pass introduced a split equality operator in the FQDN validation; that defect has been corrected. All eight HCL/example/test files were scanned for the same corruption, and a regression guard was added. This remains a source check, not a successful Terraform fmt or parse result.
- `terraform init -backend=false`: no Terraform executable or initialized provider cache. No provider binary was downloaded; no lock file was invented.
- `terraform validate` and provider-schema checks: blocked by the missing executable/provider.
- `terraform test`: the mock plan tests are supplied, but have not run.
- Azure account login, subscription reads, provider registrations, region/quota checks, deployment plan, apply, destroy, SSH, DNS/HTTP probes, effective routes, KQL execution and runtime flow verification: **not performed**.
- No cloud resources were created, modified or deleted. No repository was edited, committed or pushed.

## Required before claiming the lab works

1. Run Terraform formatting, initialize the approved pinned provider, retain/review its lock file, validate, and run mock tests.
2. Verify the actual subscription permissions, policy constraints, image/SKU/capacity, price and approved destination services.
3. Obtain deployment authorization, review the real plan, then deploy only in the dedicated lab scope.
4. Collect control-plane configuration, guest observations and correlated firewall/DNS logs. Record outcomes in `RESULTS.template.md`.
5. Perform and independently verify authorized cleanup, including billable services.

The supplied harness does not implement external UDP443/TCP22 packet-deny tests. These remain NOT RUN. If optional dig probes are skipped, DNS bypass prevention remains unverified. The sample image is latest and no provider lock file exists yet; pin a concrete image and retain the genuine lock before reproducible deployment.

Static checks and mocked shell control flow do not establish Terraform schema correctness, Azure acceptance, packet routing or security effectiveness.
