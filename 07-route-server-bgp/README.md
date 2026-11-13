# Scenario 07: Route Server learns routes; Linux NVAs carry packets

**Source-complete demo draft, not a deployed or runtime-validated environment.** This package owns the Terraform cloud topology, two FRR Linux forwarders, a controlled remote fixture, GRE/SNAT policy, private management and evidence/recovery helpers. It still requires an approved tool-complete image and operator account/access. Nothing here is a one-command production appliance or a guarantee of failover.

No cloud resource, route, BGP session, guest firewall, kernel sysctl or repository was changed while preparing the draft. Local tests are source checks, fake control/CLI tests and bounded loopback fixture requests only. Terraform/provider, FRR, nftables/kernel, Azure deployment/propagation, GRE and failover tests are **NOT RUN**. See [validation/STATUS.md](validation/STATUS.md), [RESULTS.template.md](RESULTS.template.md), [sources](SOURCES.md), the [full guide](../azure-07-route-server-bgp-nva-guide.md) and [diagram atlas](../diagrams/README.md).

These Linux nodes simulate narrowly scoped L3/L4 stateful forwarding. They are **not vendor NGFWs or a supported production NVA cluster**. No conntrack/state synchronization, DPI, TLS inspection, encryption, Internet service, ILB, VPN/ExpressRoute gateway or Azure Firewall is included. Route Server exchanges routes and programs Azure forwarding; customer packets do not traverse it. GRE is encapsulation, not encryption.

[Scenario overview](../README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

## 1. Fixed isolated topology

| Component | Exact contract |
|---|---|
| Resource group | `inspection-routeserver`, new dedicated group, explicit subscription/region |
| Hub | `hub`, 10.0.0.0/16 |
| Route Server | `routeserver`, Standard, `RouteServerSubnet` 10.0.1.0/26, separate Standard management public IP; no NSG/UDR on its subnet |
| NVA subnet/nodes | `nva`, 10.0.2.0/24; nva1=10.0.2.4, nva2=10.0.2.5; one NIC each, Azure NIC IP forwarding enabled |
| App | VNet `app`10.10.0.0/16, `workload`10.10.1.0/24, A=10.10.1.10 |
| Remote underlay | VNet `remote`10.30.0.0/16, `workload`10.30.1.0/24, R=10.30.1.20 |
| Synthetic destination | 172.20.50.0/24; D=172.20.50.10/32 on R's guest loopback, **not** any Azure VNet/NIC address |
| GRE1 | `rs-gre1`, real outer10.0.2.4↔10.30.1.20; overlay NVA1 10.255.1.1/30↔R10.255.1.2/30 |
| GRE2 | `rs-gre2`, real outer10.0.2.5↔10.30.1.20; overlay NVA2 10.255.2.1/30↔R10.255.2.2/30 |
| Private management | Standard `rs-bastion`, AzureBastionSubnet10.0.3.0/26, separate public IP; no public VM IP |
| Fixture | D TCP8080 permitted by forwarder, TCP8081 independently healthy but explicitly denied for forwarded A traffic |

Two Azure BGP connection objects `peer-nva1`/`peer-nva2` use ASN65010 and the actual NVA NIC addresses. Each guest connects to **both actual service peer IPs**, giving four sessions. Terraform sorts and exports the computed `virtual_router_ips` set and reads `virtual_router_asn`; do not guess service peer addresses. A postcondition and guest config checks require two distinct IPv4 peers in the dedicated subnet and a service ASN different from65010.

`branch_to_branch_traffic_enabled=false`; `hub_routing_preference="ASPath"`. There are no gateways to exchange routes with. Hub→app permits gateway transit and app→hub uses remote gateways/Route Server, explicitly ordered after Route Server creation. Hub↔remote has ordinary forwarded-traffic peering without gateway transit. There is no direct app↔remote peering.

## 2. Three route layers and explicit return ownership

**Azure fabric on A:** `app-routes` enables BGP propagation and contains only0/0→None. The exact learned172.20.50/24 normally selects nva1's shorter AS path. No exact /24 UDR substitutes for learning. After both advertisements withdraw, the RFC1918 system172.16/12→None or other actual winning None route drops D, with no Internet fallback. Record the actual effective source/type/state/next-hop fields; the API may label learned gateway source with `VirtualNetworkGateway`, not a literal `BGP` enum.

**Azure fabric underlay:** `nva-substrate` and `remote-routes` disable BGP propagation and contain only0/0→None. Hub/spoke system peering routes deliver outer GRE and restored app replies. No NVA fabric route points the synthetic destination back to itself. No unsupported VirtualNetworkGateway UDR is used. RouteServerSubnet and Bastion subnet have no workload UDR. Default-outbound access is explicitly disabled on NVA/app/remote subnets.

**Linux FIB:** NVAs install owned protocol186 routes to app10.10/16, remote10.30/16 and RouteServerSubnet10.0.1/26 via10.0.2.1. The synthetic /24 uses the node's own GRE remote overlay peer. R has hub10.0/16 via10.30.1.1, D local on lo and connected overlay /30 routes. Learned BGP is not installed into this deliberate guest FIB: `bgp no-rib` is configured while zebra remains active to expose local routes for network-import checking.

Forward path is A:a→D:8080, selected NVA, scoped guest forward rule, then SNAT to that node's overlay .1:q and GRE outer NVA-underlay-IP→R. R observes overlay10.255.1.1 or10.255.2.1 and the actual translated source port q. It does **not** see A. Its reply D:8080→overlay .1:q uses the connected GRE interface back to the owning NVA. That node reverses its own SNAT to D:8080→A:a and sends through hub/app peering. Route Server performs no SNAT. This deliberate per-node SNAT pins the return path but does not replicate state or preserve existing sessions if the forward BGP path moves to another NVA.

## 3. Prerequisites and gates

Required inputs are explicit subscription UUID, available approved region, existing public SSH key, exact versioned same-subscription Compute Gallery image ARM ID and exact installed upstream FRR version in the reviewed10.4 family. `deploy_lab=false` and `image_prerequisites_confirmed=false` by default. Enabling deployment requires the attestation, but an attestation is neither verification nor authorization. False after an existing deployment plans destruction, not pause.

The immutable image must already contain approved FRR10.4-family zebra/bgpd/vtysh and service integration, the `frr` account/group, Python3, Bash/coreutils/timeout, curl, iproute2/GRE kernel support, nftables JSON support, conntrack, tcpdump, systemd/cloud-init/SSH and the needed Azure guest agents. Verify exact installed version, package provenance, kernel modules, FRR daemon file semantics and image support. FRR must initially be stopped/disabled with **no existing user routing configuration**. The lab owns `/etc/frr/daemons` and its dedicated FRR configuration; do not use a shared appliance image with existing peers/secrets. No image building, software installation, update, apt bootstrap or unrestricted egress is provided.

Boot creates the owned GRE/FIB substrate and a closed forward policy. R adds its loopback and starts both fixed-data fixtures. The controller is delivered using documented cloud-init `gz+b64` encoding to stay within custom-data size bounds. Source checks estimate payload size; actual Terraform rendering/cloud-init execution remain unvalidated. On each NVA, `rs-boot.service` precedes the FRR service; it writes export-deny-all FRR config, keeps forwarding closed and starts zebra/bgpd through the supplied service dependency. **Every reboot is closed/export-withdrawn**, even if the node was previously advertised. Recovery is explicit. A failed boot/service/config parse is a blocker, not permission to bypass readiness.

Operator requirements:

- Dedicated disposable IPv4 networks with no address overlaps, dual-stack hub, existing VPN/ExpressRoute gateway or production/shared resources. Route Server creation/deletion can affect co-located gateway scenarios; this demo avoids them.
- Appropriate Azure permissions, pre-registered resource providers, quotas, approved region/SKU/image replication and a cost budget. Terraform provider auto-registration is disabled.
- Terraform>=1.9,<2 and AzureRM exactly5.12.0; approved existing authentication outside files. No secret/private key is created or requested by this lab.
- Azure CLI, existing approved Bastion extension for tunneling, SSH and Python/Bash. Helpers disable automatic extension installation. Route Server peering read commands are currently core CLI commands.
- Explicit approval for deployment, guest security/routing/BGP changes, captures and eventual deletion. A command's `--confirm-guest-change` flag acknowledges scope; it does not grant missing approval.

Protect Terraform state, plans, tfvars, logs and captures as confidential operational data. Provider-returned sensitive data cannot be excluded merely because the source has no generated password. No state backend is configured; use an approved encrypted access-controlled backend for real execution. Retain a genuine reviewed provider lockfile after approved initialization. No Terraform executable/provider cache/HCL parser was available here, and no lockfile is fabricated.

## 4. BGP and packet policy contract

FRR uses ASN65010, the actual Route Server ASN, fixed own-NIC update source, multihop eBGP and timers60/180. It explicitly originates only172.20.50/24 with network-import checking. No connected redistribution, default-originate, aggregate, IPv6 family, dynamic neighbors or Azure-local advertisements are configured.

- `RS-EXACT` permits exactly172.20.50/24.
- `RS-IN-DENY` rejects all received IPv4 prefixes; `bgp no-rib` separately prevents learned route installation. Zebra still runs.
- `RS-EXPORT-CLOSED` denies everything; boot binds it to both peers.
- `RS-EXPORT-OPEN` permits only the exact prefix, then denies the remainder. NVA2 prepends65010 twice, so the intended observed path has three65010 entries after ordinary eBGP insertion; NVA1 normally has one. **Verify actual advertised/learned paths on both service instances.**
- Per-neighbor soft-reconfiguration inbound and `maximum-prefix20 force` bound accepted plus filtered received routes; `maximum-prefix-out1` bounds export. A limit hit is a failure to diagnose, not a reason to increase limits or broaden filters automatically.

The exact approved FRR version is checked at runtime. FRR10.4 can omit enabled-default `bgp network import-check` from running-config; the checker accepts that documented default but rejects explicit disabling. Other required export/import controls, unexpected neighbor/prefix/map changes and later runtime configuration drift are checked. No `write memory` persists an open export policy. Actual FRR parsing, default normalization and origination remain untested here.

The NVA's owned `inet rs_nva` forward chain admits only original A→D:8080 NEW SYN and established traffic/replies through the appropriate GRE interface. Named `deny-alternate-8081` drops A→D:8081. Strict `nf_conntrack_tcp_loose=0` prevents permissive midstream pickup; other traffic drops. A narrowly scoped postrouting rule SNATs only A→D TCP8080 exiting that node's GRE to its overlay .1. It does not NAT BGP, SSH, other destinations or local readiness requests. GRE MTU1400 and forwarded TCP SYN MSS1360 are explicit; this is not a large-packet/fragmentation validation.

Guest input rules permit actual protocol47 only for the exact R/NVA underlay pairs and restrict BGP TCP179 to actual Route Server peers. Remote `inet rs_remote` accepts D8080/8081 only from the correct overlay peer on its corresponding GRE interface, plus local loopback readiness. It drops other decapsulated input and all forwarded traffic and does not need NIC IP forwarding. NVA host input similarly allows only exact established local-readiness replies from GRE before dropping other decapsulated host traffic. Other host management filtering still relies on the exact NSGs and approved image baseline. Never globally flush unrelated rules.

NIC NSGs: app outbound100 A/32→D/32 TCP8080/8081; NVA inbound100 same original tuple; NVA outbound101 restored D:8080→A reverse shape. SSH inbound110 is Bastion-subnet→own-IP:22. NVA BGP in/out120 is exact actual peer/own-IP TCP179. Outer underlay in/out130 is NVA/R exact /32 pairs; R uses130/131 for nva1/nva2. These outer rules use protocol `*` because the provider enum does not expose GRE. **They are not GRE-only NSG rules**; guest input rules narrow actual protocol47. Platform DNS outbound200 and other traffic4000 are denied. This also blocks ordinary unrequested egress but is not a universal claim about every exempt Azure platform channel.

## 5. Local preparation and private management

The only local check entry point below performs no installation, Terraform initialization, cloud API, FRR, nft/sysctl or guest mutation:

```bash
cd lab  # From this scenario package root
bash scripts/check-local.sh
```

Review and fill the intentionally invalid example in a separate private working copy. Supply only an existing **public** SSH key. Verify the approved image/FRR contract before changing gates. After separately approved provider initialization, future offline-capable checks are:

```bash
umask 077
cp terraform.tfvars.example terraform.tfvars
# Edit approved values; keep deploy_lab=false until deployment is approved.
terraform fmt -check -recursive
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

There are nine supplied plan-only mocked-provider cases. They still require Terraform/provider availability and do not demonstrate Azure behavior. Review the real plan, region/quota/costs and all guest changes before any separately authorized deployment. No automatic apply/destroy step is supplied.

After deployment, scope every Azure command explicitly and match the Route Server resource ID from local state:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
source scripts/common.sh
load_context
az extension list -o table
az account show --subscription "$SUBSCRIPTION_ID" --query '{subscription:id,tenant:tenantId}' -o json
terraform output -json
```

Outputs include `route_server_id`, `route_server_name`, sorted `route_server_peer_ips`, `route_server_asn`, `route_server_routing_state`, VM/NIC IDs, `private_ips`, `destination_ip/prefix`, Bastion name, image and FRR version. Provisioning/routing-state output is not readiness.

For each VM, use a separate foreground Bastion tunnel and local SSH terminal. Obtain IDs from `app_vm_id`, `remote_vm_id` or `nva_vm_ids`; do not substitute a public IP. Verify SSH host keys through the approved deployment channel.

```bash
APP_ID=$(terraform output -raw app_vm_id)
BASTION=$(terraform output -raw bastion_name)
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name "$BASTION" --target-resource-id "$APP_ID" \
  --resource-port 22 --port 50022
```

```bash
# Separate local terminal. Existing private key remains local; no insecure host-key bypass.
ssh -p 50022 labadmin@127.0.0.1
```

## 6. Staged demo with observations, not assumed results

### Closed baseline and preparation

On R run `remote-ready`: it verifies R's underlay address, D/32 specifically on lo, both active fixture units and both local D listeners/identity. The fixture returns only synthetic JSON (`azure-routeserver-origin-v1`); no real files or data. Its bounded `/stream` endpoint emits frames and a final marker. Preserve local readiness and journal evidence before treating a remote8081 timeout as a denial.

On each NVA, inspect `sudo rs-control status`, service logs and actual FRR session state. `status` reports last recorded intent and pending markers, **not observed BGP/forwarding/Azure state, lock availability or live readiness**. `check` performs read-only guest policy/config/sysctl/tunnel/listener/session checks. Local tunnel readiness binds the node's overlay IP and tests D8080 and8081 directly; it is not A's forwarded-path proof.

```bash
# Each NVA, only after approval for its exact guest routing/security change.
sudo rs-control prepare --confirm-guest-change
sudo rs-control check
sudo rs-control status
```

`prepare` withdraws exports, installs a closed table first, creates/verifies owned routes/tunnels, records original owned sysctls, configures strict forwarding and installs the scoped open table. Failure keeps forwarding closed and export withdrawn when safety operations succeed. IPv4 forwarding is set **before** rp_filter2, redirect/source-route0 and strict conntrack; it can reset other IPv4 defaults. The helper verifies its owned values, not every OS setting.

Keep both exports closed initially. Confirm no synthetic route learned and no A success using actual fabric/FRR evidence. Then explicitly advertise each prepared node:

```bash
# Each prepared NVA, separate approval. Requires both local RS sessions established.
sudo rs-control advertise --confirm-guest-change
sudo rs-control check
```

There is no background health-driven withdrawal controller. BGP availability alone is not forwarding readiness, and a later path failure does not automatically retract the advertisement.

### Positive and named negative

Verify four established sessions, exact /24 advertisement and matching per-NVA path at both Route Server instances, then A's active route through nva1. Do not generate a PASS from configuration text or a single aggregate metric.

```bash
# A: each final evidence path must be new, not precreated.
RUN=$(mktemp -d "$HOME/rs-cases.XXXXXX")
rs-probe positive --expected-node nva1 --out "$RUN/preferred-8080"
rs-probe negative --expected-node either --out "$RUN/denied-8081"
```

Positive evidence must show exact fixture/case identity and R observing10.255.1.1:q. Correlate original A:a→D:8080, NVA conntrack/SNAT, GRE outer tuple and reverse restoration on the same node. For8081, require R's independent local listener readiness, effective NSG allowance and the selected NVA's named deny/capture. A timeout without these controls is **INCONCLUSIVE**.

`rs-probe positive|negative|stream` supports `--expected-node nva1|nva2|either`, `--duration5..180` and `--out NEW_DIR`. It preserves attempted source tuple before connecting, fixed destination, case/start/end times and request-write state; records actual fixture peer/q; and does not retry/reconnect. A failed SYN sends no HTTP case header. Correlate that attempt by tuple/UTC, not a nonexistent backend request ID. A normal recorded negative/error can exit0 while remaining `NEEDS_REVIEW`; preflight errors exit nonzero. Five-second socket and finite total timeouts are independent of BGP convergence.

### Withdrawal, a single session and BGP-alive blackhole

Each bounded action accepts5..120 seconds, saves original state and events, and restores through handled HUP/INT/TERM. The requested interval is not an SLA for BGP propagation or restoration completion. If the route does not visibly change before restoration, record the experiment as inconclusive rather than inventing a backup result.

```bash
# nva1: withdraw exact prefix from BOTH peers, leave forwarding alive.
sudo rs-control withdraw-for --seconds 90 --confirm-guest-change
```

During the interval, collect Route Server learned routes and A effective route repeatedly through the approved read workflow; after actual selection of nva2, run a **new** positive case expecting nva2. R should observe10.255.2.1:q. Returning routes do not automatically move old conntrack. Unlike health-only LB withdrawal, BGP route changes may move established packets to another node and break their old SNAT/state association.

```bash
# nva1: choose one exact IP from the ACTUAL sorted Route Server peer output.
RS_PEER='REPLACE_WITH_ONE_ACTUAL_ROUTE_SERVER_PEER_IPV4'
sudo rs-control session-down-for --peer "$RS_PEER" --seconds 60 --confirm-guest-change
```

Record one administratively down session and the other retained session plus both service-instance routes. The second session should preserve that node's route, but actual fabric effects must be observed. This is not a general FRR-service crash.

```bash
# Proven current owner, with the backup ready. Deliberately keep BGP/export alive.
sudo rs-control fail-forwarding --seconds 30 --confirm-guest-change
```

This installs the closed owned forward table only; BGP sessions, advertised prefix, GRE/control and management remain in place. Expect a data blackhole while Azure still selects that node unless an unmodeled external mechanism changes routes. It does not flush conntrack, kill FRR/VMs or simulate state loss. Normal successful restoration does not gratuitously withdraw/re-advertise the unchanged BGP path. If restoration fails, the helper attempts withdrawal and closure and records which succeeded or remain uncertain.

For a separate old-flow observation, establish its original node/tuple first and start an A stream in a separate terminal before the experiment. Capture both NVAs and R. The stream never reconnects, and a five-second read timeout may end it well before a30-second failure completes.

```bash
# A, separate foreground terminal.
RUN=$(mktemp -d "$HOME/rs-stream.XXXXXX")
rs-probe stream --duration 120 --expected-node nva1 --out "$RUN/original"
```

Withdraw both nodes using approved `withdraw` actions to test loss of the learned /24 and fallback to actual None selection. This unbounded manual state change requires an explicit rollback plan; there is no claim of automatic cross-node coordination. Restore healthy forwarding first, then advertisements, then verify learned/effective route and fresh positive/negative controls.

### Evidence interfaces and limitations

```bash
# Operator computer. Fresh child path; collector checks UUID and RS resource ID.
RUN=$(mktemp -d "$HOME/rs-control.XXXXXX")
bash scripts/collect-control-plane.sh "$RUN/baseline"
```

The collector records UTC/shell exit, Terraform outputs, RS/peer objects, learned/advertised routes, all NIC effective routes/NSGs/forwarding, exact subnet/table associations, peerings and current metric definitions. API failure retains partial evidence and fails the collector. No authentication or resource creation is performed.

```bash
# Both NVAs and R in separate sessions, before A traffic; approved capture only.
sudo rs-evidence --capture-seconds 60
```

Guest evidence uses a new private directory, before/after snapshots and individual `.stdout`, `.stderr` and `.exit` files. It records FIB/address/link state, owned nft JSON/counters, scoped conntrack, FRR configuration/version/summary, each neighbor and advertised routes, plus bounded `traffic.pcap` for original/translated/outer and scoped BGP tuples. Expected capture timeout exit124 differs from command failure. Inspect **every command exit**, because the helper preserves partial observations rather than turning missing commands/data into PASS. Guest `ip route` is not Azure's effective route table. `tcpdump -i any` can show multiple local copies; do not count them as separate end-to-end flows.

For Azure metrics, use actual definitions and split BGP peer status/counts by peer and service instance. Current guidance recommends Maximum and at least5-minute chart granularity, which cannot prove instantaneous four-session health or packet continuity. The displayed “Data Processed by the Virtual Hub Router” metric does **not apply** to Route Server. No firewall/application/session logs are invented for the control-plane service.

## 7. Locks, recovery, rollback and cleanup

The exclusive lock covers an entire bounded interval and restoration. Concurrent mutating `close`, `withdraw` or `recover` **cannot override** a live experiment and fail immediately. `status` does not acquire or check that lock. Let the exact process finish, or use an approved handled interruption of that known process; inspect events/status, confirm process exit and lock release, then issue another action. Never delete the lock file or kill arbitrary processes to bypass it.

Ordinary actions are not atomic across both peers. Before prepare/advertise/withdraw/close/restore-original/recover/reconcile, the controller durably writes `transition.json`. A partial peer change, command error or state-write failure triggers best-effort export withdrawal and owned-table closure, records which commands succeeded or remain uncertain, and retains the marker. Even successful commands do not establish actual remote withdrawal. A marker blocks reopening, bounded experiments and `recover`; read-only status/check and lock-free close/withdraw/reconcile remain available. Successful close/withdraw retries do not silently clear earlier uncertainty.

Use explicitly approved `reconcile` to force closed forwarding and withdrawn exports, then verify both local CLOSED export filters and empty advertised-prefix JSON for each peer. Only successful local verification and state persistence clear `transition.json`. Missing, unexpected or still-populated observations keep it pending. This does not prove Azure convergence. It never clears the separate bounded `recovery.json`; if both markers exist, reconcile first, then separately approve recovery of the old state. Do not manually delete either marker to bypass guards.

```bash
# Relevant NVA, after its old process exited/released the lock; deliberately closes it.
sudo rs-control reconcile --confirm-guest-change
sudo rs-control status
# Verify both service-instance/Azure withdrawals separately before reopening.
```

Persistent events are under `/var/lib/azure-routeserver-lab/experiments/<action>-<time_ns>/events.jsonl`; a private `recovery.json` records original flags, owned sysctls and attempt path. HUP/INT/TERM support does not cover SIGKILL, power loss, inaccessible storage or every restoration failure. A leftover bounded recovery marker blocks prepare/advertise/restore-original until handled; an ordinary transition marker has the additional restrictions above. Once the lock is free, close/withdraw remain available without erasing it. Manual recovery starts export-withdrawn, restores the owned substrate/policy, verifies readiness and may re-advertise the recorded state; approve that consequence explicitly.

```bash
# Relevant NVA only, after examining its pending record/events and process/lock state.
sudo rs-control status
sudo rs-control recover --confirm-guest-change
sudo rs-control check
```

For normal rollback, stop traffic, withdraw lab exports on both nodes, verify actual withdrawal at both service instances and A, then close owned data policies. `restore-original` optionally restores only captured owned sysctl values and removes the owned sysctl persistence file. It does not remove GRE/FIB interfaces, undo every OS setting, erase unrelated filters or delete conntrack. Routes/tunnels live inside the disposable VMs and are removed with their separately approved destruction.

```bash
# Each NVA, only after any bounded controller has exited/released its lock.
sudo rs-control withdraw --confirm-guest-change
# Verify actual withdrawal using scoped read evidence before the next step.
sudo rs-control close --confirm-guest-change
# Optional owned-sysctl rollback; requires no pending recovery marker.
sudo rs-control restore-original --confirm-guest-change
```

Save approved bounded evidence, inspect a destruction plan against the dedicated state/resource group, confirm no shared resources were imported, and follow the operator's approved deletion workflow. Do not delete Route Server as the first recovery action, delete a shared gateway/image/key, or discard state before verifying teardown. Check residual disks/IPs/Bastion/RS charges and follow approved evidence retention/disposal. Closing policy or stopping traffic does not stop billing.

## 8. Cost and explicitly missing validation

Budget for four VMs/disks, Azure Route Server service capacity, Standard Bastion, two Standard public IPv4 resources, peering/data transfer, the prebuilt image/storage/replication and any chosen monitoring/export. Azure price, currency, regional availability and subscription offer must be checked in the [pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) before approval. No cost total is fabricated.

Not implemented as bundled variants: propagation-disabled/exact-/24-UDR experiments, Route Server route maps, ILB next-hop alternative, gateway/branch exchange, public ingress, vendor clustering, state replication, encryption, IPv6, throughput/scale, ECMP/load balancing, region/zone resilience or real VM crash. Azure service-side Route Server route maps are currently a separate preview capability with upgrade/extra-charge considerations; this lab uses only FRR-local maps. ILB next hops are another alternative not used here. Service-side preview restrictions must not be conflated with the NVA's own-AS prepend. Every Azure/FRR/GRE/kernel/runtime outcome in the worksheet remains NOT RUN until separately authorized execution and evidence review.
