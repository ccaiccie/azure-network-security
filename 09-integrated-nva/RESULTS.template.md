# Scenario 09 results worksheet

**Every Azure/vendor/actual-guest result starts NOT RUN.** Local fake CLI/guarded-loopback checks are recorded separately. This worksheet is not observed network evidence.

Keep this worksheet and collected outputs/logs private. Azure CLI query filtering is client-side, diagnostics may contain sensitive fields, and declared Terraform outputs/profile text are copied without redaction. Enter no secrets in profile fields; review and redact an approved copy before sharing.

## Ownership and selected product

- Approved subscription/region/operator/change windows/cost budget: NOT RUN
- Exact approved image, Terraform/provider lock and schema checks: NOT RUN
- Owned WAN/hub, app/origin/management VNets, actual D and management paths: NOT RUN
- Selected NVA publisher/offer/plan/version/scale, software/manager version and current support reference: BLOCKED until selected
- External NVA/managed app/managed RG IDs and actual linked hub: NOT RUN
- License/onboarding/health and supported owner/deletion path: NOT RUN
- Projected identity comparison and freshness: NOT RUN (MATCH would still not verify vendor policy)
- Stable vendor policy package/primary8080/alternate8081 rule IDs and no broad competing Allow: NOT RUN
- Complete final public E pool, intermediate S:r distinction, source provenance and update method: NOT RUN

## Readiness and paths

- App local tool/config/NIC checks; origin exact8080/8081 local health: NOT RUN
- App Bastion in management10.40/16, subnet10.40.2/26; both management/app peering directions with no gateway/forwarded transit: NOT RUN
- Management/origin have no hub connections/default propagation; origin no peering to app/management: NOT RUN
- Source selected route to D, competing system/default/more-specific routes, no UDR0/0None: NOT RUN
- Internet-only intent, connect-app internet_security_enabled and actual Default/Default association/propagation: NOT RUN
- Hub defaultRouteTable and vendor direct-egress/reverse-to-A routes: NOT RUN
- Exact source/origin NSG100 Allow only after prerequisite review; original vs mapped tuples correct: NOT RUN
- Actual safe public runtime JSON D/E and case-specific snapshot: NOT RUN

## Cases

For each attempt retain original `A:a -> D:p`, actual UTC start/completion, evidence path, TCP/HTTP stage, actual installed vendor revision/action/rule/session-owner, intermediate tuple if present, final `E:q -> B:p`, fixture identity/case and all relevant route/NSG snapshots. q need not equal a. An origin E-pool match alone does not prove source A or intended policy.

| Case | Required evidence | Status |
|---|---|---|
| Bootstrap isolation | Both NSG100 Deny, no intent before vendor setup; local management/readiness only | NOT RUN |
| Closed8080 | Healthy origin, exact NSG envelope Allow, correct paths and named vendor Deny | NOT RUN |
| Positive8080 | Named installed Allow, original/final translation correlation, matching fixture from approved E:q | NOT RUN |
| Alternate8081 | Separately healthy8081, named installed vendor Deny, correct NSGs/paths | NOT RUN |
| Finite existing stream | One socket/tuple and frame timeline versus actual vendor-supported policy/session closure | NOT RUN |
| Fresh after closure | Newly attempted tuple, current installed Deny and matching log | NOT RUN |
| Pre-removal isolation | Clients stopped, origin units inactive/listeners absent, vendor closure and both NSG100 Deny verified | NOT RUN |

Denied SYNs do not deliver HTTP case headers. Missing origin logs or timeout alone is inconclusive. Missing or ambiguous vendor logs are BLOCKED/INCONCLUSIVE, not PASS. A log showing an external-private translated tuple is not necessarily the final public E:q.

## Removal and residual costs

- Supported vendor closure and existing-session outcome: NOT RUN
- Origin units inactive and successful listener query empty; clients stopped: NOT RUN
- Both exact NSG envelopes Deny and isolation verified despite stateful-flow caveat: NOT RUN
- Intent reference removed only after isolation; propagation side effects reviewed: NOT RUN
- External managed application/NVA/license assets removed through authorized owner, no protected-child bypass: NOT RUN
- Owned infrastructure removed only after external dependency resolved; RG safeguard respected: NOT RUN
- Residual vendor/service/public-IP/disk/log costs checked; image/keys preserved; evidence/state retention approved: NOT RUN

Default withdrawal/instance failure/state synchronization are not implemented experiments in this package.
