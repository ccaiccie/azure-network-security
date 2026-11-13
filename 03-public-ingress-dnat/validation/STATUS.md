# Validation status

Checked 4 November 2026. **Draft only. No Terraform/provider or Azure validation.**

## Passed locally

- `bash -n` for four shell scripts and 19 Markdown Bash fences, without executing the documented commands.
- 48 focused source-contract checks: publication gating/default off, required public/32 source guards, exact DNAT wiring, computed P/F, no additional firewall allows/custom SNAT, two peerings, backend private subnet/no public NIC IP, route-resource ownership and blackhole scope, translated-source NSG, private management, owned fixtures, diagnostics and curl safeguards.
- 26 local Python tests: real synthetic fixture only on 127.0.0.1:8080; JSON peer/server identity, ignored client XFF, no file serving, long-path/POST rejection, readiness with real local HTTP plus fake service/IP/socket tools; fake-curl positive/negative/input-validation cases; fake Azure/Terraform collector verifying scoped read-only calls and extension preflight; manual CLI subscription guards; and the README listener contrast using fake sudo/systemctl for normal restoration, expected inactive status under errexit, EOF, stop failure, missing readiness and restoration failure. No real service command ran.
- Python source compilation without writing bytecode; test listener closed after the suite.
- Manual source review against the supplied brief and official Azure/provider documentation.

Complete output: `local-checks.txt`. Machine-readable scope: `report.json`. Cleanup: `listener-cleanup.txt`.

## Supplied but not run

Eleven Terraform provider-mocked plan-only runs assert unpublished default, exact backend NSG tuples, private topology, exact published DNAT collection/rule/ports/source, complete last-route deletion, exact firewall-subnet return blackhole, rejected broad/documentation/private/shared/multicast/IPv6 sources and rejected unpinned image. These are **not counted as passed local tests**.

Terraform/OpenTofu are absent, so fmt, init, validate and Terraform test remain unexecuted. Source checks are not an HCL parser. No provider was downloaded and no genuine lock file was generated. The pinned 5.12.0 NAT documentation fetch failed; official main-branch docs were used, so the exact schema still needs verification.

The systemd unit was not loaded, started or verified here. An earlier lab's systemd verification attempt could not initialize due to read-only `/run/systemd`; this draft does not bypass that restriction. Local fixture tests do not establish cloud-init/systemd boot success.

No Azure login, source-IP verification, resource/provider/quota/pricing query, real Terraform plan/apply/destroy, deployment, Bastion session, cloud listener test, public request, route query, packet capture or KQL execution occurred. No repository was edited or pushed.

## Before claiming a deployed working lab

1. Validate the exact pinned provider and all Terraform mocks; retain a genuine lock and approved concrete image.
2. Verify approved subscription/region/permissions/extensions/capacity/cost and actual public source/32. Review and authorize the real plan and Internet exposure.
3. Establish private management and fresh local readiness of the owned B:8080 service.
4. Collect actual P/F/policy/source/mapping/NSG/peering/routes and the external positive: HTTP200, B identity, observed I:q, original-client NAT row and return route to I.
5. Run the unpublished-port negative and healthy control. Excluded-source testing requires a second controlled network and actual source evidence; otherwise leave NOT RUN/INCONCLUSIVE.
6. Separately authorize any experiment, restore exact baseline and verify evidence. Withdraw publication or delete only with the applicable authorization, then verify the intended outcome and remaining billing.

## Dated deployment prerequisite

On 4 November 2026, Microsoft's current capacity table lists new East US Azure Firewall Standard deployments as blocked. README, source record, variable description and example comments now flag this; the original eastus default was not changed. Recheck capacity and approve any region change before deployment.
