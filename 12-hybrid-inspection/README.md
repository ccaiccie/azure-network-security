# Scenario 12: hybrid private inspection lab

**Source-complete Terraform demonstration draft, not a deployed or runtime-validated network.** It owns an Azure-hosted branch simulation, two VPN gateways and two conditional VNet-to-VNet connections, a hub Azure Firewall Standard, a spoke, private fixtures, private VM management and logging. It does not validate a physical branch, BGP, ExpressRoute, FastPath, carrier service, transport failover or seamless session continuity.

Read the [full scenario guide](../azure-12-hybrid-vpn-expressroute-inspection-guide.md), [sources](SOURCES.md), [validation status](validation/STATUS.md) and [results worksheet](RESULTS.template.md). No deployment, cloud read, PSK generation/retrieval/transmission, repository change or real guest mutation occurred while preparing this draft.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. Opening these files executes nothing.

## 1. Owned resources and route contract

Use a **new dedicated** resource group, default `inspection-hybrid`, in one approved Azure public-cloud subscription and availability-zone region. Never import existing production routes, gateways or subnet associations.

- `branch`,172.16.0.0/16: `workload`172.16.10.0/24, VM/NIC `branch`/`branch-nic`, A172.16.10.10. Local `AzureBastionSubnet`172.16.250.0/26. `GatewaySubnet`172.16.254.0/26.
- `hub`,10.0.0.0/16: `AzureFirewallSubnet`10.0.1.0/26 and `GatewaySubnet`10.0.254.0/26. Firewall `hub-firewall`, policy `hybrid-policy`, public IP `firewall-public-ip`. **F is the actual output `firewall_private_ip`, not a hardcoded .4.**
- `spoke`,10.20.0.0/16: `workload`10.20.1.0/24, VM/NIC `spoke`/`spoke-nic`, B10.20.1.20.
- `management`,10.40.0.0/16: `AzureBastionSubnet`10.40.2.0/26. Four ordinary peerings connect management with hub and spoke, without gateway transit, remote gateways or forwarded traffic. No branch peering or direct branch-to-spoke shortcut.
- `hub-vpn-gateway` and `branch-vpn-gateway`: route-based `VpnGw1AZ`, `Generation1`, active-standby, BGP disabled, one Standard/static IPv4 public IP each (`hub-vpn-public-ip`, `branch-vpn-public-ip`), zones1/2/3. Each gateway contains managed instances; this is not a two-circuit failover lab. The rest of the topology is not made zone-resilient by this setting.
- Reciprocal `hub-to-branch` and `branch-to-hub` connection resources use `Vnet2Vnet` and the same operator-supplied PSK. No VPN NAT, custom IPsec policy, traffic selectors, ExpressRoute or forced tunnel.
- `branch-bastion` and `azure-bastion`: Standard,2scale units, native tunneling, own public IPs. The VMs have no public NICs and disabled default outbound access. Bastion's required service traffic is distinct from workload permissions.
- `hybrid-logs`:30-day Log Analytics workspace, local authentication disabled. Firewall resource-specific `AZFWNetworkRule`/`AZFWThreatIntel`; gateway `GatewayDiagnosticLog`/`TunnelDiagnosticLog`/`RouteDiagnosticLog` and metrics. Delivery/schema require runtime checking.

The six hub/spoke/management peering resources are explicit. Only `hub-to-spoke` allows gateway transit; only `spoke-to-hub` uses the remote gateway. Both allow forwarded traffic. No other peering carries transit.

| Subnet | Table and exact routes | Gateway propagation |
|---|---|---|
| Hub GatewaySubnet | `gateway-to-spoke`:10.20.0.0/16→VirtualAppliance F | Enabled |
| Branch GatewaySubnet | No customer table or NSG | Default enabled |
| AzureFirewallSubnet | No customer table or NSG | Default enabled |
| A workload | `branch-safety`:0.0.0.0/0→None | Enabled |
| B workload | `spoke-return`:172.16.0.0/16→F;0.0.0.0/0→None | Disabled |
| Both Bastion subnets | No customer route table | No forced/default tunnel |

**No NSG, /0 route or gateway-address interception on GatewaySubnet.** Do not put the whole hub prefix through F. Workload /0 discards are Internet isolation, not steering. The propagated spoke /16 should beat A's discard routes; verify the actual route. A Connected tunnel alone is insufficient. Suppression on B prevents even a more-specific propagated branch /24 from bypassing F. Longest prefix comes before equal-prefix source precedence.

Firewall routing toward B should use peering and toward A the propagated branch VPN route. A/B socket tuples are expected unchanged because these are private-address network rules without NAT. Inner TCP A:a→B:8080 is distinct from public VPN tunnel endpoints and encrypted transport. Numeric HTTP here does not demonstrate TLS decryption.

## 2. Prerequisites, secrets and cost

Required: approved subscription/RBAC, registered Microsoft.Network/Compute/OperationalInsights/Insights resource providers, quotas, an available region supporting this AZ gateway/public-IP combination, Standard Firewall, Bastion and chosen VM size, an existing SSH **public** key, and an existing same-subscription concrete Compute Gallery image version. The image must already have Python3, iproute2 (`ip`, `ss`), systemd, cloud-init, SSH and a working Azure guest agent. No runtime download/package rule or image build is supplied. Review its baseline host firewall and tools separately.

Region is required, with no default. On **4 November2026**, Microsoft's [capacity table](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues) still blocks new Standard Firewall deployment in East US and lists other restrictions. Recheck current capacity before choosing. Gateways commonly need45minutes or more to provision; an elapsed timer is not readiness evidence.

Local operator tools: already-approved Terraform>=1.9,<2, AzureRM exactly5.12.0, Azure CLI, Python3, Bash and SSH. Bastion native commands require the already-installed approved Bastion extension; helpers disable automatic extension installation. No Terraform lock file was fabricated. Obtain and review the genuine dependency lock/checksums during approved initialization. Pinned provider schema, region behavior and all Azure operations remain unvalidated here.

**PSK boundary:** `vpn_shared_key` is a nullable, sensitive input. It must remain null while `create_connections=false`. When enabling both connections, an authorized operator supplies the **same existing approved high-entropy PSK** through their approved secure runner/secret-input mechanism, for example secure injection into `TF_VAR_vpn_shared_key`. This text does not generate or request a key. Never paste it into chat, examples, source control, ordinary shell history, CLI arguments or logs. The alphanumeric32–128character validation is a portability/format guard, not an entropy test. Mock-test public sentinels must never be used for a real connection.

**Sensitive does not mean state-free. Terraform receives the supplied PSK and persists it in plans/state/backups.** Environment injection does not change that. Protect backend storage, locking, access, encryption, plan artifacts, backups, logs, crash files and local process environments under the operator's credential policy. This lab does not create or secure a backend. Never publish `terraform show`, raw state, saved plans, key panels or shared-key endpoint results. AzureRM can also store Log Analytics `primary_shared_key`/`secondary_shared_key` even with local authentication disabled. Declared lab outputs intentionally omit these secrets, but are not a universal redaction boundary. Tags, metadata, error text and captured response data require private review.

A no-PSK-in-Terraform-state architecture would need externally owned connection creation and a different lifecycle contract. **It is not an implemented mode here.** This lab owns both connections when enabled and their later deletion. No external circuit or vendor subscription is created.

Main charges: two `VpnGw1AZ` gateways, Azure Firewall Standard hourly/data processing, two Standard Bastions with2units each, two VM/disks, **five Standard public IPs**, gateway transfer/peering, and Log Analytics ingestion/retention. No exact quote is invented. Use the current [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for the approved region and duration. Leaving VMs stopped does not stop gateway/firewall/Bastion/public-IP charges.

## 3. Eight false-by-default stage gates

`deploy_lab`, `image_prerequisites_confirmed`, `create_connections`, `connections_ready`, `private_routes_verified`, `fixtures_ready`, `test_paths_enabled`, `allow_test_flow` all default false. Readiness fields are historical human attestations, not live observations, permission or automated checks.

1. Review sources, inputs, costs, approved image, secret/backend handling and provider schema. Fill only nonsecret fields in a private working copy of `terraform.tfvars.example`.
2. After authorized provisioning review, substrate stage sets only image attestation and deployment true. Both gateways/firewall/UDRs/NSGs/Bastions/VMs exist, but connection resources are absent and primary policy/test NSGs are Deny.
3. After separately authorized secure PSK input and plan review, enable `create_connections`. Both reciprocal connection resources are owned together. Verify their intended peers, health and every required route; do not infer success from provisioning completion.
4. Check each endpoint's local fixture identity and management path. Record route evidence before setting the three readiness flags. Keep test NSGs and primary policy Deny during preparation.
5. Set only `test_paths_enabled=true` after readiness. Exact NSG test envelopes open while Firewall primary stays Deny, allowing meaningful closed-path attribution.
6. Set only `allow_test_flow=true` for the primary positive/stream. The two negative Firewall collections remain Deny.
7. Restore primary Deny and verify actual policy/flow closure. Stop clients/listeners, close test NSGs and prove isolation before removing routes, connections or topology.

Changing `deploy_lab=false` in an existing state is a destruction request, not a pause. Changing `create_connections=false` deletes connections, not a reversible transport failover test. Also set `connections_ready=false` when removing connections. Withdraw the secure PSK input so it is null in that stage; old state/plan/backups remain secret-bearing until securely disposed. No apply/destroy commands are executed or included in this runbook. A combined plan does not promise security-safe update ordering. Keep the routing and inspection topology intact until isolation has been independently established.

Local checks only:

```bash
./scripts/check-local.sh
```

Future approved provider preparation, separate from this draft's checks:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

Initialization may download providers and is **not offline**; backend=false does not imply network-free or make an existing state safe. All17supplied tests are mock-provider, plan-only. Never substitute a live provider. Neither these tests nor `validate` verifies Azure deployment, tunnel negotiation, effective routes or packet behavior.

## 4. Private management and local readiness

From the lab directory, on the approved operator computer, require explicit subscription and verify the declared identities before any Azure read/tunnel. `common.sh` validates UUID, RG, exact firewall/policy/workspace, both VMs/NICs, four VNets, two gateways/public-IP IDs, three tables, both Bastions and connection-stage map. It accepts allocated F within the intended subnet, not a guessed IP.

```bash
export SUBSCRIPTION_ID='REPLACE-WITH-APPROVED-UUID'
source ./scripts/common.sh
load_context
require_extensions bastion
```

In separate terminals, open each approved native management tunnel, then use the existing local private key only through SSH. The VM admin key is not a VPN PSK and is never copied into Terraform.

```bash
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name branch-bastion \
  --target-resource-id "$(read_map_output vm_ids branch)" \
  --resource-port 22 --port 50222
```

```bash
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name azure-bastion \
  --target-resource-id "$(read_map_output vm_ids spoke)" \
  --resource-port 22 --port 50223
```

```bash
: "${SSH_KEY_PATH:?Set existing approved private SSH key path locally}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes -p 50222 \
  "$(read_output admin_username)@127.0.0.1"
# In another shell use port50223 for the spoke. Verify SSH host keys independently.
```

Do not bypass host-key warnings. Branch management is local, B management returns through its management-VNet peering; neither needs the hybrid test flow or primary Allow. Verify the actual management return route rather than claiming absolute independence from all platform faults.

On **each guest**, reserve fresh private evidence and run installed readiness:

```bash
umask 077
READY_RUN=$(mktemp -d "$HOME/hybrid-ready.XXXXXX")
if hybrid-ready > "$READY_RUN/readiness.json" 2> "$READY_RUN/readiness.stderr"; then
  printf '0\n' > "$READY_RUN/readiness.exit"
else
  rc=$?; printf '%s\n' "$rc" > "$READY_RUN/readiness.exit"
  printf 'Local readiness failed; stop the demo.\n' >&2
fi
```

Runtime config `/etc/azure-hybrid-lab.json` has exactly `role`, `private_ip`, `branch_ip`, `spoke_ip`. Role `branch` runs `azure-hybrid-fixture@8082.service`; role `spoke` runs @8080/@8081. Python listens only on the fixed private address, with synthetic marker `azure-hybrid-fixture-v1`. `/health` and `/probe` return socket/case/UTC identity; only B8080 serves bounded `/stream?seconds=N`. `hybrid-ready` checks own NIC, exact active units and source-bound local HTTP identity. `LOCAL_FIXTURES_READY` is not tunnel, Firewall or remote-route proof.

## 5. Control-plane and packet evidence

Default collector reads only exact guarded IDs, reserves a new directory and preserves every read's JSON/stderr/exit, start/end UTC and a private-handling receipt. It does not run guest probes, inspect raw VM bootstrap, invoke shared-key endpoints, modify resources or auto-install extensions.

```bash
./scripts/collect-control-plane.sh
```

By default, existing connection GETs are skipped and `connections-SKIPPED.txt` requests sanitized operator evidence. At initial stage an empty declared connection map yields `connections-NOT-ENABLED.txt`. Missing/null/malformed required maps are rejected before Azure reads. If the authorized operator explicitly approves receiving the potentially sensitive full connection response in their private CLI environment:

```bash
./scripts/collect-control-plane.sh --acknowledge-sensitive-connection-response
```

The optional flag makes exactly two verified `vpn-connection show` requests. `--query` is client-side filtering; the full response arrives first. The generic API schema lists `sharedKey`, so omission is not guaranteed by this draft; no actual receipt is claimed. Never enable debug/tracing or share raw errors/cache/output. Even without the opt-in, all metadata/outputs remain private review-required. Reads that return empty/null or fail are not route/health proof. Collector0 means reads completed, not a working or inspected network; any read failures exit3.

Required evidence before opening primary Allow:

- Both intended connection IDs, reciprocal peer gateway IDs and observed Connected/tunnel state. Null status, partial status and aggregate counters are inconclusive. BGP status is irrelevant because BGP is disabled. Observe gateway diagnostics/metrics with actual dimensions and UTC, not fabricated values.
- A effective route for B selects a gateway-propagated remote spoke prefix. Do not label it BGP. If missing, stop and fix supported transit/connection configuration, never add a direct peering workaround.
- Hub GatewaySubnet association, exact10.20/16→actual F route and propagation enabled; no default/NSG/control-prefix overlap.
- B effective route172.16/16→F and propagation disabled. Firewall onward path to B is peering and to A is the branch VPN route. There is no promised effective-route command against hidden managed Firewall/gateway NICs; combine supported route/config observations, logs and both-direction traffic evidence, with any onward uncertainty explicit.
- Actual NSG100forward/101reverse test envelopes Allow,110SSH only respective Bastion,200AzurePlatformDNSDeny,4000otherDeny. Platform agent/service behavior is separate from general egress. Stateful returns do not imply arbitrary inbound/outbound Allow.
- Policy `hybrid-policy`, group `hybrid-rules` priority200. Collections: `deny-healthy-alternate`100→`deny-branch-alt-8081`; `deny-reverse-new`110→`deny-spoke-new-8082`; `test-flow`200→`branch-to-spoke-8080`. No parent, application or NAT rules.

On **A**, once exact test NSGs are open and primary policy is still Deny:

```bash
hybrid-probe closed
```

After the separately reviewed primary Allow becomes effective:

```bash
hybrid-probe positive
hybrid-probe alternate
hybrid-probe stream --duration 60
```

On **B**, while its reverse8082 NSG envelope is open and A8082 healthy:

```bash
hybrid-probe reverse
```

Each helper creates a unique private case directory under `~/hybrid-evidence`; optional `--out NEW_PATH` refuses existing files/directories/symlinks. Never reuse a previous case directory. The bound attempted tuple and start UTC are durably stored in `connection.json` **before SYN**. `connected.json`, request-started/request-written, `frames.ndjson` and `result.json` preserve stages, completion UTC, errors, expected/observed peer tuple and stream outcome. A denied SYN cannot carry an HTTP case header; correlate its exact tuple/time. Headers/case ID are only available after an actual request write, which itself is not delivery proof.

Clients use literal addresses and fixed allowed ports, no DNS/proxy/redirect/retry/reconnect. Socket timeout5s, fresh total15s, stream5–180s plus10s total grace. A stream socket can fail earlier than its requested duration. All results say `NEEDS_REVIEW`, including HTTP200. Do not use process exit0 as PASS.

| Case | Required corroboration, not just client outcome |
|---|---|
| Closed primary8080 | Healthy B8080, exact NSGs open, actual route chain, named primary Firewall Deny row for attempted tuple |
| Positive8080 | Correct complete fixture response/body/case and original peer A:a; named primary Allow and both-direction route evidence |
| Alternate8081 | Healthy B8081, same path, `deny-branch-alt-8081` Deny; no claim from timeout alone |
| Reverse-new B→A8082 | Healthy A8082, reverse NSG envelope open, `deny-spoke-new-8082` Deny; distinguish from established8080 response |
| Stream/closure | Same held socket and bounded frames; change primary to Deny only in approved stage and record actual old-flow and fresh-flow behavior separately |

Use [network-rule.kql](queries/network-rule.kql) with actual tuple/start/end/firewall ID and [gateway-events.kql](queries/gateway-events.kql) for private diagnostics. Log ingestion is asynchronous; absence does not prove denial or lack of traffic. Fixture journals contain synthetic content but topology/case metadata still require review. Microsoft's Firewall rule-change guidance says relevant sessions are dropped when Allow becomes Deny; this does not establish immediate completion/timing in this deployment. NSG rule changes have different existing-flow behavior. Measure both.

## 6. Isolation, rollback and cleanup

No route-bypass, propagation-toggle, tunnel-reset, transport-failure or real ER/FastPath variant is implemented. Those require a separately scoped review, guaranteed management/recovery and actual alternate transport where relevant.

1. Stop initiating clients and let bounded streams finish or interrupt their exact process. Restore primary Firewall Deny; verify current policy plus fresh denial and ended old connections.
2. Through retained management, stop the exact owned listeners and verify both successful unit reads and successful empty listener queries. On B:

```bash
sudo systemctl stop azure-hybrid-fixture@8080.service azure-hybrid-fixture@8081.service
for unit in azure-hybrid-fixture@8080.service azure-hybrid-fixture@8081.service; do
  state=$(systemctl show "$unit" --property=ActiveState --value) || exit 1
  [[ "$state" == inactive ]] || { printf 'Listener unit is not inactive.\n' >&2; exit 1; }
done
listeners=$(sudo ss -H -ltn 'sport = :8080 or sport = :8081') || exit 1
[[ -z "$listeners" ]] || { printf 'A test listener still exists.\n' >&2; exit 1; }
```

On A:

```bash
sudo systemctl stop azure-hybrid-fixture@8082.service
state=$(systemctl show azure-hybrid-fixture@8082.service --property=ActiveState --value) || exit 1
[[ "$state" == inactive ]] || exit 1
listeners=$(sudo ss -H -ltn 'sport = :8082') || exit 1
[[ -z "$listeners" ]] || exit 1
```

3. Close `test_paths_enabled`, verify both NSGs and that prior flows have ended. A stopped service is not persistent through reboot while enabled; keep policy/NSGs closed. If reopening later is separately authorized, restart the exact units and repeat local/full route readiness before any gate reopening.
4. Only after steps1–3 have established and recorded isolation may an authorized operator review removal of both connections. Keep `deploy_lab=true` and `image_prerequisites_confirmed=true` so the gateway, firewall, routes and management substrate remain present. In that separately reviewed connection-removal stage, use all of these values together:

```hcl
allow_test_flow = false
test_paths_enabled = false
fixtures_ready = false
private_routes_verified = false
connections_ready = false
create_connections = false
vpn_shared_key = null
```

Withdraw any secure runner/environment PSK injection so the effective value really is null; do not display the prior secret. A stale `connections_ready=true` correctly rejects a plan when connections are disabled. Resetting readiness flags only clears historical attestations; it does not itself stop traffic. This connection-removal stage follows verified isolation and retains both Bastions and steering routes. Review its plan for exactly the intended connection deletions and no unexpected substrate changes. Old state/plan/backups remain secret-bearing.

**Removing the GatewaySubnet/spoke UDR while workloads remain open can restore a direct gateway/peering bypass.** Route removal or full-topology teardown is a subsequent separately reviewed stage, not an implicit part of clearing readiness. Destroy ordering is not isolation. No automatic prior-resource restoration is promised because this lab must own a new disposable topology.
5. Review deletion of both owned connections before their gateways; firewall, VMs/NICs/disks, three route tables/associations, six peerings, logs and public IPs must all be accounted for. Retain both Bastions until endpoint isolation and required evidence are complete. Do not delete the external approved image or existing SSH key.
6. Review residual resources/charges and dispose of PSK/plan/state/backups/evidence under the operator's retention and secret policy. There is no carrier contract, external license or real ExpressRoute circuit to cancel in this fixture.

## 7. Validation meaning

The local suite separately reports fixture/probe loopback tests, fake-CLI identity/collector tests, a small route-selection teaching model and source-text assertions. They are not a Terraform interpreter, actual route table, IPsec negotiation or Azure control plane. Service unit parsing is not systemd execution. Cloud-init compressed source size is an estimate, not an evaluated Terraform render. The actual provider schema, deployment, secret injection, gateway/transit behavior, routes, management, firewall state/logs, fixture services, packets, costs and teardown all remain **NOT RUN**. Complete the worksheet with real observations only after authorized deployment.
