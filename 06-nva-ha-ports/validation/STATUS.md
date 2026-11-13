# Validation status

Last local check: **2026-11-04 UTC**. Scope: this independent draft directory only. No repository changes, credentials, deployment, cloud API calls or actual guest security operations.

## Passed here

- **135 text/AST source-contract assertions**, including topology count, same-F routes, NVA nonrecursive route table, exact transit NSG shapes, probe/all-unhealthy settings, guarded image/deployment inputs, guest control/evidence contracts and no deliberately generated private key/NAT resource. These are text assertions, not an HCL parser or provider schema.
- **56 Python unittest cases**: 36 fake-backend/controller cases, 12 fixture/client cases and 8 process-level mocked Azure/Terraform collector cases. Controller subprocess security calls cannot execute in the fake backend. Loopback requests validate only the local Python fixture/client. The collector sees fake CLI executables and never contacts Azure.
- Python AST parsing of **6 Python files**, Bash syntax of **7 helpers**, basic INI structure for **4 systemd units**, and Bash syntax of **14 README code fences**.
- Regression coverage includes SIGHUP/INT/TERM handler registration, bounded restoration and persistent start/end event records, pending-recovery baseline protection and live-lock refusal of concurrent mutations, health versus forwarding separation, strict state admission source, sysctl sequence mocked verification, source tuple persisted before a connect timeout, no request-write claim after failed connect, complete versus truncated streams, and nonclobbering evidence directories/subscription mismatch.

The exact controller/fixture split above follows unittest classes; see [local-tests.txt](local-tests.txt). Systemd parsing does not validate sandbox behavior. Fake nft JSON does not validate actual nft syntax, JSON output, table behavior, kernel conntrack, rp_filter, capability execution or real sysctl persistence.

## Supplied but NOT RUN

- **10 Terraform plan-only mocked-provider cases** in `tests/baseline.tftest.hcl`: disabled root; deployment attestation; exact HA topology/routes/NSGs/probe; optional zones; invalid zone combinations; concrete same-subscription image; private-key rejection.
- Terraform fmt, init, validate, tests, provider schema/type checks and a real plan. Terraform/OpenTofu, HCL parser and AzureRM provider cache are unavailable. No installation/download or lockfile generation attempted. Provider 5.12.0 is pinned in source only.
- `nft -c` syntax check and any real nft table load; actual nftables/conntrack/tcpdump tools absent. No security settings changed to simulate them.
- Image contents, cloud-init/custom-data acceptance, systemd service execution, private SSH/Bastion, region/SKU/quota/price/access verification.
- All real Azure resource creation, route/NSG/LB/NIC reads, LB metric queries, effective next-hop checks, packet capture and backend/client/NVA runtime observations.
- Forwarding/symmetry, actual probe convergence, all-unhealthy behavior, old/new-flow handling, failover, real VM/state loss, zone resilience, rollback and cleanup verification.

No pass count above establishes production readiness or an Azure result. The design is a synthetic strict Linux forwarding model without vendor NGFW features or synchronized conntrack. An existing approved tool-complete image is still required before an on-demand deployment can be attempted.
