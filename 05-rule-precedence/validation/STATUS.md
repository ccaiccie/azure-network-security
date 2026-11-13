# Validation status, 2026-11-04

## Completed locally

- Five Bash helpers parsed with `bash -n`; twelve README Bash fences parsed without executing their commands.
- Python fixture/helper-test source parsed with AST.
- Systemd unit parsed as INI and its expected executable/hardening fields asserted. No system service was loaded or started; no `systemd-analyze` runtime validation is claimed.
- 98 focused source assertions passed: closed/readiness/experiment gates, mode/rule/priority/hostname/port wiring, source-preserving/proxy backend NSGs, exact UDR prefixes/F references, private DNS child IDs, Bastion, explicit subscription, no packages or secret/access-grant resources.
- 44 local tests passed:12 fixture tests (loopback HTTP plus CLI input guards),24 helper tests with fake curl/getent/Azure CLI/Terraform, and8 readiness tests with mocked subprocess/HTTP controls. Additional regression cases cover nonempty/empty/symlink output refusal, fixed-path rerun preservation and distinct default directories, collector refusal and persisted start/completion timestamps including a handled DNS failure. These validate local helper logic, not actual DNS, policy evaluation, proxy SNAT, route selection or guest systemd behavior.
- Naive HCL delimiter counts inspected, **not** an HCL grammar parse or provider check.
- Current official Microsoft and HashiCorp documentation reviewed. AzureRM5 Private DNS A/link resources corrected to `private_dns_zone_id`; version-tagged documentation fetches for these DNS resources were unavailable, so official current/5.x references were used instead. The pinned5.12 Log Analytics workspace documentation was fetched and reviewed, including exported shared-key state risk.

The actual local run is `local-checks.txt`. Mock/loopback output is synthetic and cannot fill the runtime results template.

## Supplied but NOT RUN

Eleven plan-only mocked-provider runs in `tests/baseline.tftest.hcl`: root disabled, closed infrastructure, readiness-alone closed, application baseline, network Allow, network Deny, application restored and invalid mode/readiness/approval/image inputs. No mock apply is supplied. Mock tests still require Terraform and the installed provider schema; they have NOT RUN here.

## Not available or not attempted

- Terraform/OpenTofu executable and HCL parser are unavailable. `fmt`, `init -backend=false`, `validate`, provider schema checks, mock Terraform plans and real plans are NOT RUN. No provider lockfile was generated and Terraform formatting is not certified.
- No Azure tenant/authentication command, resource/DNS/policy creation/change/deletion, upload or apply. No key/certificate/secret generation, retrieval, access grant or repository change.
- No real Azure DNS proxy/private-zone resolution, actual selected-image bootstrap, Bastion session, effective Azure route/NSG inspection, network/application rule match, managed proxy source observation, origin packet capture or diagnostic ingestion test.
- Standard region capacity/quota, resource availability, costs and provider/API acceptance remain unverified. East US Standard restriction is a dated documentation observation, not a live deployment test.
- Inheritance, DNAT, Premium TLS/IDPS, reverse-new and generic bypass variants are conceptual/not implemented, not missing claimed passes.

This is an on-demand executable **draft**, with staged operator prerequisites and explicit validation gaps, not a demonstrated successful Azure deployment.
