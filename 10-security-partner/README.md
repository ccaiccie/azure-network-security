# Scenario 10: Security Partner Provider cloud-delivered egress

**Azure-side source draft, not self-contained end-to-end ZIA automation.** This package creates the owned vWAN/VPN/SPP/HTTP-fixture substrate and evidence tools. An approved Zscaler ZIA account, license, supported onboarding, authorized Azure access, partner-created tunnels, protected hub-routing activation, location/client policy and provider logs are **external prerequisites**. No credentials, grants, licenses, tunnels or ZIA policy were created here.

All Azure/provider/actual-guest results are **NOT RUN**. Recovery on 6 November 2026 completed offline Terraform formatting and a passing recursive format check using an already-available reviewed executable. Initialization, provider/schema validation, real plans and the supplied mocked-provider plans remain NOT RUN; formatting is not their substitute. The original local-suite counts are historical, not fresh full-suite results. See [validation/STATUS.md](validation/STATUS.md), [RESULTS.template.md](RESULTS.template.md), [SOURCES.md](SOURCES.md) and the [full guide](../azure-10-security-partner-provider-guide.md). The final guide link is resolved by package assembly.

This is **Firewall Manager Security Partner Provider**, not an integrated NVA in the hub, an Azure Firewall substitute label or direct-in-hub SaaS. The Azure SPP association is not a packet endpoint and does not install the external service. Current dedicated Microsoft SPP deployment guidance names Zscaler; older overview/provider enums are not commercial-support evidence for other products.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. No command is executed by opening this README.

## Owned topology and external ownership

- RG `inspection-spp`; Standard WAN `lab-wan`; managed hub `spp-hub`, `10.0.0.0/23`.
- Hub VPN gateway `spp-vpn-gateway`, reviewed `vpn_scale_unit` default1. Conditional SPP `spp-zscaler`, `security_provider_name="ZScaler"`, explicitly depends on that gateway.
- App VNet `app`, `10.10.0.0/16`; workload `10.10.1.0/24`; VM/NIC `app`/`app-nic`, **A=10.10.1.10**. No public NIC IP, NAT Gateway, outbound LB, alternate proxy/Client Connector or implicit default outbound access.
- `connect-app` is the only hub connection. Terraform owns `internet_security_enabled=enable_source_default`, false initially. It omits custom routing blocks. There is no workload UDR, no manually advertised0/0, and **no azurerm_virtual_hub_routing_intent resource pointing at SPP**.
- Unconnected origin VNet `origin`, `10.30.0.0/16`; workload `10.30.1.0/24`. VM/NIC `origin1`/`origin1-nic`, **B1=10.30.1.20**, and `origin2`/`origin2-nic`, **B2=10.30.1.21**. Each has its own actual allocated Standard public IPv4 D1/D2, never a documentation example.
- Both origins run the singleton `azure-spp-fixture.service` on **TCP80**, marker `azure-spp-origin-v1`. The service uses DynamicUser and only CAP_NET_BIND_SERVICE to bind port80, with read-only filesystem/process hardening. App has no listener.
- Independent management VNet `management`, `10.40.0.0/16`; app-bastion in AzureBastionSubnet `10.40.2.0/26`. Peer only management↔app with VNet access, **no forwarded traffic, gateway transit or remote gateways**. No management hub connection or UDR. App returns to management over its more-specific10.40/16 peering route.
- Origin Bastion is local in `10.30.2.0/26`. Both are Standard/native-client Bastions with mandatory service NSGs and public HTTPS service endpoints. SSH target access is private; neither is Premium private-only Bastion. Origin is not peered or connected to app/hub/management.

ZIA onboarding owns its approved integration credentials/access, location, provider-created VPN sites/connections, tunnel settings and provider policy. The supported Firewall Manager/ZIA workflow owns protected **hub** routing activation; this module implements only the app connection's explicit opt-in. Agree field ownership before activation so external tools do not silently fight Terraform. Do not assume scenario09's Internet-intent Default/Default association or its virtual-hub-router dataplane bypass applies here. Record actual SPP route tables, association/propagation and path.

## What the packet evidence must distinguish

For a request to Di:80:
1. A binds and records **A:a -> Di:80** before SYN. Its NSG sees original source A and public destination Di.
2. Azure must select the observed protected default and appropriate hub/gateway path. Guest routes or a successful SPP create are insufficient. Unknown /32/split-default overrides or alternate egress invalidate the experiment.
3. IPsec VPN transport carries the inner flow between actual gateway endpoint **G** and service endpoint **Z**. The vpn_gateway_public_ips output supplies computed gateway endpoint candidates, not a verified G↔Z pairing. Record real outer addresses, protocol/NAT-T and selectors; do not assume UDP4500/ESP or confuse G/Z with provider public web egress E.
4. ZIA applies the activated location/client web/category policy. Allowed HTTP can be **proxied**, with separate client-side and upstream TCP sessions. No shared TCP sequence space, source-port preservation, or one transparent NAT session is assumed.
5. Upstream reaches public Di as **E:q -> Di:80**. Azure maps Di to private Bi, so the origin NSG/fixture sees **E:q -> Bi:80**. E is an approved observed provider pool member; q need not equal a.
6. Origin returns through its public-NIC mapping to E:q. ZIA associates the upstream response with the client-side transaction, returns it through the service tunnel/gateway, and A observes its requested Di endpoint. Provider-native logs must establish that association.

An HTTP **Block** can complete TCP and return an HTML200/403 block page, reset or time out. Timeout is not required. HTTP200 alone is not a positive. Require the controlled fixture marker/body/case and origin/provider transaction evidence. A synthetic page without matching activated rule/action/location evidence is not proven policy enforcement. Tunnel Connected or byte counters do not prove the web policy matched.

## NSGs, public exposure and gates

Priority100 `test-web-egress` on app permits only A/32→D1/D2 TCP80 when opened. Each origin's `test-web-ingress` permits only the complete reviewed E/32 pool→its own private B:80. All default to Deny. Empty-E bootstrap uses a **Deny-only** wildcard source; no broad Allow is permitted.

Priority110 permits management10.40.2/26→A22 and origin-local10.30.2/26→each B22. Priority200 denies AzurePlatformDNS outbound; priority4000 denies other inbound/outbound. Replies to permitted requests are stateful. Platform infrastructure exceptions still exist; this is not zero-platform-communication proof. Default outbound access is explicitly false on workload subnets, but that setting alone is not a route, firewall or universal failclosed guarantee.

D1/D2 are real Internet-facing plain-HTTP service addresses, initially blocked and later restricted to E. Provider E may be shared across tenants; allowlisting E does **not** authenticate A or a person. Use only synthetic content and require provider location/client/policy evidence. Never broaden origins to Internet because E inventory is incomplete.

Eleven boolean gates default false:
- `deploy_lab` and `image_prerequisites_confirmed`.
- `enable_spp`: Azure association only, requiring the selected nonsecret provider profile.
- `provider_onboarding_verified`, `tunnels_verified`, `provider_routing_configured`: separate external prerequisites before app opt-in.
- `enable_source_default`: Terraform-owned app opt-in only, not hub routing creation.
- `protected_routes_verified`, `fixtures_ready`, `provider_block_policy_verified`.
- `test_paths_enabled`: exact endpoint NSG opening after all prior readiness and nonempty E.

Attestations are not permission, automation or continuous health checks. `provider_block_policy_verified` is the **initial** activated Block baseline, not current action after a later Allow test. There is no Terraform ZIA-Allow toggle. `deploy_lab=false` after deployment plans destructive removal, not a pause.

## Prerequisites and secret handling

Select an available approved region, disposable subscription UUID, appropriate quota/permissions and registered providers. Confirm actual tenant/region/SKU/license eligibility and gateway capacity before spending. No provider registration is performed automatically. Gateway deployment can be lengthy; Terraform completion is not tunnel readiness.

Require an existing approved same-subscription versioned Compute Gallery image with Python3, iproute2, SSH, systemd, cloud-init and functioning Azure guest agent. Review the hardened unit and low-port capability on that image. No package/image build, public bootstrap downloads or installation is included. Supply an existing approved SSH **public** key only; keep private keys on the operator computer.

Terraform >=1.11,<2 and AzureRM5.12.0 are declared. The package minimum supports plan-stage computed-value overrides in the bundled mock tests; it is not an Azure service-version requirement. No genuine lock exists because init was not run; create/review one only through approved tool/provider setup. Current official provider docs were reviewed, but the exact executable/schema, plan graph and API acceptance remain unvalidated. Existing authenticated Azure CLI and approved already-installed `virtual-wan`/`bastion` extensions are required; helpers disable automatic extension installation and never sign in.

`provider_profile` is intended only for operator-reviewed nonsecret references: ZIA cloud/tenant/location/license/support, approved Azure application/principal UUIDs, this dedicated RG scope, role/expiry owner references, routing owner and category/rule/activation/evidence references. It does not create service principals or grant access. New persistent access and credential transmission need separate action-time approval and secure entry through the appropriate service, **never this repository, tfvars, chat, cloud-init or an ordinary JSON file**.

Do not request shared-key endpoints, SP secrets, passwords or tokens, export complete connection JSON, or enable `--debug`, `--verbose` or shell tracing. Do not import externally created VPN connections merely to inspect them. Azure CLI `--query` filters returned JSON **client-side**, not on the server. The [2025-05-01 Swagger](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/network/resource-manager/Microsoft.Network/Network/stable/2025-05-01/virtualWan.json) documents link sharedKey omitted from Get/List responses and the legacy connection key deprecated/unused; this draft does **not** claim those reads return PSKs. That server behavior, rather than output filtering, is the documented key-omission mechanism. Full returned metadata, tags, errors and SDK/CLI logs can still contain sensitive text. Default collection therefore skips the VPN connection-list read as a conservative local choice; optional per-invocation acknowledgement is explained below. See [Microsoft's CLI query documentation](https://learn.microsoft.com/cli/azure/use-azure-cli-successfully-query).

**Profile free text is not automatically redacted.** Enter no credentials, license keys, signed/bootstrap URLs, tokens, personal or other sensitive data in any profile field or resource tag. The collector copies declared Terraform outputs, including the profile, without redaction and retains per-read stderr. Guest HTTP body evidence can also contain sensitive text despite bounded capture and selected header redaction. Keep all state, plans, tfvars, outputs, evidence, logs and backups private in approved encrypted access-controlled storage. Review and redact an approved copy before any sharing. Neither the schema nor these scripts guarantee secret-free evidence; no general automatic redaction or harmless-state claim is made. No state backend is created.

## Staged future setup

1. Prepare inputs with all gates false:

```bash
cp terraform.tfvars.example terraform.tfvars
: "${PUBLIC_KEY_FILE:?Set approved existing PUBLIC key file}"
export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
./scripts/check-local.sh
```

The example deliberately has invalid placeholders. After separately approved tool/provider setup, preparatory non-deployment commands are:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

Init can download provider code and was not run here. The supplied cases use mock-provider plans. Real plans may authenticate/read Azure; review diff, cost, image, rendered cloud-init and state handling before separately authorized execution. No apply/destroy command is embedded or executed.

2. First authorized infrastructure stage sets only deploy_lab/image_prerequisites_confirmed true: hub, gateway, protected management and three workloads exist; SPP, source default and test paths remain off.
3. Complete the selected nonsecret `profiles/provider-profile.example.json` and supply the typed profile, for example:

```bash
: "${APPROVED_PROFILE_FILE:?Set reviewed NONSECRET provider profile JSON}"
export TF_VAR_provider_profile="$(cat "$APPROVED_PROFILE_FILE")"
```

The profile requires existing approved identity UUIDs and exactly this dedicated RG scope, not subscription-wide permission. If a supported integration cannot work within the approved ownership/scope, stop and resolve that prerequisite; do not silently expand access.
4. Separately authorize enable_spp=true. The Azure resource depends on the VPN gateway; it may be Succeeded while connectionStatus is Unknown. This is not a completed integration.
5. Complete external ZIA licensing, approved authorization, integration synchronization/location/tunnel creation using its supported workflow. Record provider-created connection/site IDs and **both Azure and ZIA sides' required tunnel inventory/state**. Do not create duplicate connections or manually inject0/0 BGP. Mark onboarding/tunnels verified only from real evidence.
6. Verify both origins locally. Review actual complete E inventory, at most16 unique global IPv4 addresses disjoint D1/D2. If the complete actual pool exceeds16, this bounded lab is BLOCKED pending a reviewed redesign; never truncate the inventory or broaden origin access. Reject documentation/private/shared/multicast/reserved addresses. Configure literal-IP custom categories for D1/D2 and initially activated **Block** in the exact lab location/client context. Confirm no exception/broad Allow defeats it and record activated revision/log schema.
7. Use the supported external owner to activate protected hub SPP routing while NSGs remain closed. Then separately authorize the Terraform app opt-in enable_source_default=true. Record actual selected0/0, current hub association/propagation/connection origins, tunnel path and independent management. No fixed routing-intent semantics are assumed. Refresh/review for external computed-field drift; do not blindly overwrite service-owned values.

## Private management and fixture/config readiness

On the operator computer, `load_context` checks the explicit subscription, six core network IDs, both origin public-IP IDs, all three VM IDs, the exact app/origin1/origin2 NIC-ID map, and the optional SPP ID against expected resource group/type/name. This is a declared-output identity guard, not proof of authorization, resource existence or guest reachability:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
source ./scripts/common.sh
load_context
require_extensions bastion
: "${SSH_PRIVATE_KEY_FILE:?Set existing approved local SSH key path}"
az_read network bastion ssh -g "$RG" -n app-bastion \
  --target-resource-id "$(read_map_output vm_ids app)" --auth-type ssh-key \
  --username "$(read_output admin_username)" --ssh-key "$SSH_PRIVATE_KEY_FILE"
```

For either origin use origin-bastion and vm_ids origin1/origin2. Preserve host-key checking and approved target permissions. App Bastion resides outside the default-learning VNet; origin management is also unconnected to the hub. Do not use a Bastion-subnet UDR workaround.

On each intended guest:

```bash
umask 077
READY_RUN=$(mktemp -d "$HOME/spp-ready.XXXXXX")
spp-ready > "$READY_RUN/readiness.json"
sudo cloud-init status --long > "$READY_RUN/cloud-init.txt"
ss -ltn > "$READY_RUN/listeners.txt"
```

App readiness checks local config/tools/NIC only. Each origin checks its exact singleton service, private IP and local HTTP80 identity. Empty E is allowed only for startup/local readiness and reported as pool_not_ready; not as traffic readiness. Cloud-init keeps E=[] permanently so an E-pool change does not replace VMs.

Generate nonsecret runtime files from actual declared outputs:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
umask 077
CONFIG_RUN=$(mktemp -d ./runtime-config.XXXXXX)
./scripts/make-runtime-config.sh app "$CONFIG_RUN/app.json"
./scripts/make-runtime-config.sh origin1 "$CONFIG_RUN/origin1.json"
./scripts/make-runtime-config.sh origin2 "$CONFIG_RUN/origin2.json"
```

These local-only helpers write new0600 files, validate distinct public D1/D2 and complete E, and upload nothing. Review the five top fields role/private_ip/app_ip/origins/egress_public_ips; origins contains each fixed private B and allocated public D. Copy only the corresponding public JSON through the intended already approved Bastion-native transfer path. No `/etc` rewrite is required. On the guest:

```bash
: "${PUBLIC_RUNTIME_CONFIG:?Set reviewed public JSON on this intended VM}"
export SPP_LAB_CONFIG="$PUBLIC_RUNTIME_CONFIG"
spp-ready
```

A change in D/E invalidates earlier endpoint/category/routing evidence. Close tests and re-review before new traffic.

## Read-only evidence and demo cases

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
./scripts/collect-control-plane.sh
```

Optional OUT must not exist. The collector saves declared outputs, scoped WAN/hub/management/SPP/gateway metadata, app opt-in/current hub route views, all NIC routes/NSGs, management peerings/subnets and D1/D2 public mappings. Each read preserves normal JSON output/stderr/exit; timing includes completion UTC/shell exit. `PRIVATE-HANDLING-REQUIRED.txt` explains client-side filtering and unredacted output/diagnostic retention. Failed reads or an opted-in incomplete page cause exit3. The collector never automatically follows arbitrary nextLink or calls shared-key endpoints; it does not intentionally export complete VPN connection JSON.

**Default: VPN connection-list GET is skipped**, with `vpn-connections-SKIPPED.txt` and `vpn_connection_read_opted_in=false` in summary.txt. Obtain separately authorized, reviewed/sanitized Azure connection/link inventory and state from the responsible operator, plus ZIA-side evidence. Exit0 with this deliberate skip does not satisfy tunnel verification.

If that specific Azure read is authorized and the operator understands the full returned JSON is received before filtering and diagnostics may be sensitive, opt in for that invocation only:

```bash
# Use a new nonexistent private evidence path. This is not needed for default collection.
: "${ACKNOWLEDGED_CONTROL_OUT:?Set a NEW private output path after reviewing full-response handling}"
./scripts/collect-control-plane.sh --acknowledge-full-vpn-response "$ACKNOWLEDGED_CONTROL_OUT"
```

The optional flag records `vpn-response-read-ACKNOWLEDGED.txt` and `vpn_connection_read_opted_in=true`, then requests2025-05-01 once and filters normal stdout to connection/link identities, states and counters. It does not create authorization or guarantee redaction, and is not remembered by the next invocation. Unknown long options are refused. The documented key omission is unchanged; this opt-in is a conservative handling boundary, not an assertion that PSKs are returned. Preserve private errors/nextLink and incomplete results; use separately reviewed evidence before conclusions.

Empty/null status, no connections, Succeeded or Connected are **not health/policy proof**. route_verification, tunnel_verification and provider_policy_verification remain NOT_PERFORMED. A nextLink or unsupported/empty view must be resolved before conclusions. The API versions are documented source candidates, not runtime-validated commands. Required manual evidence includes actual both-side tunnel set, observed G/Z transport, selected routes, activated ZIA location/client/category/rule/revision/action, available transaction/original/upstream tuple fields, provider E inventory and origin journal. Native ZIA schema is required, not Azure Firewall KQL. Missing tuple/log fields must be disclosed, never fabricated.

After route/fixture/activated baseline Block evidence, attest protected_routes_verified/fixtures_ready/provider_block_policy_verified and authorize test_paths_enabled=true. Verify exact NSG100 Allow on app and both origins; otherwise a timeout cannot be attributed to ZIA. On A:

```bash
spp-probe closed
```

Expected baseline: correlate the original case/URL/tuple/time with **activated D1 Block**. Preserve observed HTTP block response/reset/timeout. A denied or intercepted SYN may deliver no HTTP case at origin; correlate available provider fields honestly.

Through the supported ZIA workflow activate **D1 Allow only**, retain D2 Block and preserve Azure path. Record activated revision before testing:

```bash
spp-probe positive
spp-probe alternate
```

Positive requires a complete matching origin1 marker/case/body at B1:80, observed peer E:q, provider transaction/action evidence and actual origin journal. Unique case URLs and no-store request/response headers reduce cache ambiguity, but caching/rewrite behavior must still be recorded; never invent an origin request from a cached response. Alternate uses independently healthy origin2 D2/B2:80 and requires the named activated D2 Block, not merely no origin record.

Optional finite existing-session observation while D1 Allow is effective:

```bash
spp-probe stream --duration 180
```

Observe valid frames, then perform supported provider closure/activation with timestamps. No retry/reconnect occurs; a five-second socket timeout and finite total deadline bound observation. Provider update timing may exceed the window. Do not import Azure Firewall's session-revocation semantics; measure the existing flow and a fresh closed attempt separately. A block page can be client-side HTTP even without an upstream connection.

Helpers always return **NEEDS_REVIEW**: exit0 records an attempt, not network PASS. They preserve public runtime config, pre-SYN attempted tuple, connected/request-write stages, actual response headers/status (sensitive header values redacted) and bounded raw nonfixture body, frames and final completion/error. OUT paths are nonclobbering. An interrupted process can leave incomplete stages; preserve them. Response identity validates E:q at private Bi, not original-source preservation or a transparent TCP/NAT path. The bounded body may still contain unexpected provider authentication/SSO material: keep it private, review/redact before sharing and never upload it automatically. Files include runtime-config.json, connection.json, connected.json, request-started.json, request-written.json, response-headers.json, frames.ndjson, response-body-prefix.bin (8192-byte cap) and result.json. Observations distinguish FIXTURE_RESPONSE, PARTIAL_FIXTURE_RESPONSE, FIXTURE_IDENTITY_MISMATCH, NON_FIXTURE_HTTP_RESPONSE, TRANSPORT_TIMEOUT, TRANSPORT_RESET_OR_CLOSED and ATTEMPT_FAILED; block_proven and provider_path_proven remain false. See the guide for the correlation worksheet.

## Closure, ownership-aware teardown and costs

1. Stop finite clients; activate exact provider Block through the supported workflow and prove fresh denial. Establish existing-session closure separately.
2. Stop exactly azure-spp-fixture.service on **both** origin VMs through independent management. Verify each unit inactive and a successful listener query shows no TCP80 service. Preserve journals/evidence.
3. Close test_paths_enabled while infrastructure remains. Verify source and both origin NSG100 Deny plus actual isolation. NSGs are stateful; changed rules alone do not terminate every established flow.
4. Only after isolation, remove app default opt-in through Terraform's owner and restore/remove hub protected routing through its recorded external owner. Observe actual remaining routes; no universal fail-open/fail-closed or automatic rollback guarantee exists.
5. Unlink the integration/location and provider-created VPN sites/connections using the supported external workflow. Never delete gateway first or assume deleting SPP cancels vendor billing/access. Inventory dependencies because partner-created sites may not be visible in the portal.
6. Separately review removal of owned SPP, gateway, hub/WAN, connection, management peerings/three VNets, three VMs/disks, two Bastions and four owned public IPs. Preserve existing image/keys. Respect unexpected-resource safeguards and provider ownership; do not bypass deny assignments or blindly target-delete resources.
7. Any credential/grant revocation, license cancellation or shared manager change needs separate ownership-aware approval. Confirm no unrelated usage, residual charges or unfinished cleanup; protect state/evidence under approved retention.

Budget ZIA license/service/log costs, Standard vWAN/hub, VPN gateway scale units/connections, two Standard Bastions, three VMs/disks, four owned public IPs, peering and Internet/tunnel transfer, and any provider-side logging. Closing rules/stopping VMs does not stop all those charges. Use current region/offer/provider pricing and [Azure calculator](https://azure.microsoft.com/pricing/calculator/); no quoted price or cap is asserted.

This baseline proves nothing about TLS inspection, user authentication, private transit, malware/DLP, branch routing, service failure or seamless session preservation. Tunnel/gateway failure and default withdrawal are not implemented experiments. End-to-end readiness remains blocked until the supported external integration and required real evidence exist.
