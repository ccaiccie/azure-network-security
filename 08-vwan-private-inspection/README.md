# Scenario 08: Standard vWAN secured hub private inspection

**Complete source draft, not a deployed or provider-validated lab.** Local tests exercise Python on guarded loopback and fake CLI responses only. Terraform formatting, initialization, validation and supplied mocked-provider plans are **NOT RUN** because Terraform and a provider cache are absent. Every Azure provisioning, effective-route, Firewall logging, Bastion, image, fixture and inspection outcome remains **NOT RUN**. See [validation/STATUS.md](validation/STATUS.md), [RESULTS.template.md](RESULTS.template.md), and the [full guide](../azure-08-vwan-private-inspection-guide.md).

This disposable lab implements Azure Standard Virtual WAN, one managed secured hub with Standard Azure Firewall, two connected spoke VNets, private workloads and **two local Standard Bastions**. It does not reuse an existing production hub. There are no branch gateways, VPN, ExpressRoute, inter-hub connections, explicit VNet peerings, customer hub VNet, AzureFirewallSubnet, ILB, NVA, DNAT, application/TLS inspection or Internet routing policy. Additional variants in explanatory material are conceptual, not implemented here.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

## Topology and packet contract

- Resource group `inspection-vwan`; WAN `lab-wan`; managed hub `secured-hub`, `10.0.0.0/23`.
- Firewall `hub-firewall`, `AZFW_Hub`/Standard; policy `private-policy`. Use actual private/public IP outputs, never an assumed hub IP.
- App VNet `app`, `10.10.0.0/16`; workload `10.10.1.0/24`; VM `app`, NIC `app-nic`, **A = 10.10.1.10**.
- Backend VNet `backend`, `10.20.0.0/16`; workload `10.20.1.0/24`; VM `backend`, NIC `backend-nic`, **B = 10.20.1.20**.
- Both run the synthetic, nonsecret HTTP fixture `azure-vwan-origin-v1`: B listens on **8080 and 8081**, A on **8082**. No HTTPS or authentication claim is made for these private test listeners.
- Connections `connect-app` and `connect-backend` omit `routing` entirely. The intent `private-inspection` has one `PrivateTrafficPolicy`, destination `PrivateTraffic`, next hop the **Firewall resource ID**. Both connections have Internet security disabled.

Azure routing intent owns connection association/propagation and platform steering. Do not add competing routing blocks, custom hub route tables, static connection routes or route maps. This lab relies on **no virtual hub router dataplane** traversal: the router is a logical routing-decision illustration, while intent programs the Azure platform path through the Firewall. Observe actual NIC and hub route views rather than predicting a specific NIC prefix/next-hop representation.

Each workload subnet has `${role}-outbound-safety`: propagation enabled, only `0.0.0.0/0 -> None`. This blocks generic outbound routing and is **not** the Firewall steering route. Private intent routes must remain available and win as appropriate. No `remote /16 -> Firewall IP` UDR is installed. Workload default outbound access is false. NSGs explicitly deny AzurePlatformDNS and other unapproved workload traffic; the probes use numeric IPs and need no DNS. Azure platform infrastructure exceptions still exist, so this is not a proof of zero communication with all Azure infrastructure.

For the RFC1918 network-rule flow, expected tuple at B is original `A:ephemeral -> B:8080`; default network-rule private SNAT behavior is unchanged. The response belongs to this established state. A **new** `B:ephemeral -> A:8082` request is a separate denied case, not proof that established replies are blocked. Verify original IP **and port** at the fixture. A successful HTTP response alone cannot establish that Firewall was traversed.

## Policy and exact NSG envelope

Rule collection group `private-rules`, priority **200**:

| Collection | Priority | Action | Rule / tuple |
|---|---:|---|---|
| `deny-healthy-alternate` | 100 | Deny | `deny-app-alt-8081`, A/32 to B/32 TCP8081 |
| `deny-reverse-new` | 110 | Deny | `deny-backend-new-8082`, B/32 to A/32 TCP8082 |
| `test-flow` | 200 | Deny by default, opt-in Allow | `app-to-backend-8080`, A/32 to B/32 TCP8080 |

Threat intelligence is Alert. No parent policy or unbounded allow exists. Rules and collection names remain stable when changing the primary action.

Each workload NIC NSG has:
- Priority100: exact forward A/32 to B/32 TCP8080,8081, outbound on A and inbound on B.
- Priority101: exact new reverse B/32 to A/32 TCP8082, inbound on A and outbound on B.
- Priorities100/101 are **Deny until `test_paths_enabled=true`**, then Allow so the Firewall controls these test cases.
- Priority110 inbound permits SSH only from that VM's own local Bastion `/26` to its private `/32`.
- Priority200 outbound denies AzurePlatformDNS; priority4000 denies other inbound/outbound traffic.

Each Bastion has its own mandatory service NSG and no workload route table. App Bastion subnet is `10.10.2.0/26`, backend is `10.20.2.0/26`. Bastion public service endpoints are Internet-facing HTTPS management endpoints; **the VMs have no public IPs**. This is private target access via public Standard Bastion, not the Premium private-only Bastion SKU. Management does not require opening the cross-spoke test rules.

## Prerequisites, authorization and state protection

1. A disposable Azure public-cloud subscription, explicit approved UUID and **explicit available region**, sufficient permissions and quota. No region default is selected. Recheck [current Firewall capacity issues](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues), Standard vWAN/secured hub, Bastion, image and VM availability. A region label in mock tests is not a capacity finding.
2. Already registered `Microsoft.Network`, `Microsoft.Compute`, `Microsoft.OperationalInsights` and relevant monitoring providers. Provider automatic registration is disabled. No registration or permission creation is performed by this draft.
3. An **existing approved same-subscription versioned Compute Gallery image** containing Ubuntu-compatible systemd, cloud-init, Python3, curl, iproute2 (`ip`/`ss`), SSH and a functioning Azure Linux guest agent. No image creation, package downloading, apt update, public package egress or software installation helper is included. Verify no custom guest firewall, proxy, forwarding or preload conflicts; verify the fixed private IP config and service units are supported. The exact version ID is required, not `latest`.
4. An existing approved SSH public key and access to its private counterpart on the operator computer. Only public text is a Terraform input; never copy private keys to this project, cloud-init, Terraform variables/state or a VM. No key generation or credential transmission is included.
5. Approved Terraform >=1.9,<2 and AzureRM **5.12.0**. The genuine provider lock file is absent because initialization was not performed. Create/review the genuine lock through approved provider setup later; do not fabricate checksums. Current official docs were reviewed, but pinned schema/runtime execution remains unverified.
6. Existing authenticated Azure CLI and approved, already installed `virtual-wan`, `azure-firewall` and `bastion` extensions for the associated commands. CLI extensions can otherwise auto-install; helpers explicitly set `AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no` and refuse missing dependencies. No auto-login or installation is performed. Logs can be queried in the approved Azure portal without installing a query extension.

**Treat Terraform state and plan files as secrets.** AzureRM may export Log Analytics `primary_shared_key` and `secondary_shared_key` into state even with local authentication disabled. Public keys, resource metadata and generated infrastructure identifiers also appear. Do not commit state, plans, tfvars, credentials, raw all-state dumps or evidence. Use an approved encrypted, access-controlled state backend and handle backups and local evidence with equivalent care. No backend is automatically created here, and `terraform output -json` is limited to the declared nonsecret output interface. Connection metadata can still be sensitive.

## Safe gates and preparation

All six booleans default false:
- `deploy_lab`: creates no resources in empty state; switching it false after deployment plans **destruction**, not pause.
- `image_prerequisites_confirmed`: operator attestation, not a permission grant or automated image verification.
- `fixtures_ready`: actual local healthy B8080/B8081 and A8082 checks reviewed.
- `private_routes_verified`: actual intent, associations, propagated NIC routes, Firewall onward routes and relevant NSGs reviewed.
- `test_paths_enabled`: opens only the exact workload NSG test envelope after deployment and both readiness attestations.
- `allow_test_flow`: opens only A-to-B8080 at Firewall after all preceding readiness and NSG gates.

Copy/edit the example locally, supply only the existing public key, then run local source checks:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit the UUID, region and approved image version. Keep all gates false initially.
: "${PUBLIC_KEY_FILE:?Set existing approved PUBLIC key file}"
export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
./scripts/check-local.sh
```

The placeholders intentionally fail validation. After separate approved tool/provider setup, these are preparatory, non-deployment commands:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

`init` may download provider code; it was not run here and is not automatically run by `check-local.sh`. The supplied tests are mock-provider **plan** tests, not actual Azure plans or deployments. A real plan may read Azure and authenticate. Review actual provider schema, rendered cloud-init, resource diff, cost and state handling before any separately authorized provisioning. This draft intentionally executes or embeds **no apply/destroy command**. Later approved deployment should use `deploy_lab=true`, `image_prerequisites_confirmed=true`, and the remaining gates false. Keep managed connections/intent changes serialized and wait for actual convergence, not merely a CLI success message. Run a fresh review plan after intent has mutated computed association/propagation to identify drift; do not blindly force the old values back.

## Private management and fixture readiness

On the operator computer, use the lab's state-matched context and existing SSH credentials. The common helper requires an explicit UUID matching the Firewall/hub resource IDs before any resource read:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
source ./scripts/common.sh
load_context
require_extensions bastion
: "${SSH_PRIVATE_KEY_FILE:?Set existing approved local SSH private key path}"
az_read network bastion ssh -g "$RG" -n app-bastion \
  --target-resource-id "$(read_output app_vm_id)" --auth-type ssh-key \
  --username "$(read_output admin_username)" --ssh-key "$SSH_PRIVATE_KEY_FILE"
```

For B, replace only `app-bastion`/`app_vm_id` with `backend-bastion`/`backend_vm_id`. The native client uses the existing local key; never print or upload its contents. Host-key verification and ordinary Bastion authentication/permissions remain required.

On **each** VM, record a fresh private readiness directory:

```bash
umask 077
RUN=$(mktemp -d "$HOME/vwan-readiness.XXXXXX")
vwan-ready > "$RUN/readiness.json"
sudo cloud-init status --long > "$RUN/cloud-init.txt"
ss -ltn > "$RUN/listeners.txt"
```

`vwan-ready` verifies role, fixed config, local non-loopback IP, exactly the expected active `azure-vwan-fixture@PORT.service` instances, each unit active, and source-bound local HTTP identity. A's only fixture is8082; B's are8080/8081. It is not a cross-spoke or Azure route test. Inspect cloud-init failure output, journal and local health before setting `fixtures_ready=true`. Provisioning success, cloud-init submission or a mock test alone is insufficient.

Preserve journals for actual cases using fresh private files and actual UTC boundaries:

```bash
umask 077
JOURNAL_RUN=$(mktemp -d "$HOME/vwan-journal.XXXXXX")
: "${START_UTC:?Set actual case start UTC}"
: "${END_UTC:?Set actual case end UTC}"
sudo journalctl -u 'azure-vwan-fixture@*' --since "$START_UTC" \
  --until "$END_UTC" --output=short-iso-precise > "$JOURNAL_RUN/fixture-journal.txt"
```

## Route and control-plane evidence

Before opening NSGs, and again after each policy change:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
./scripts/collect-control-plane.sh
```

Optional positional OUT must **not exist**, including an empty directory or symlink. Automatic names are unique per process/time; no overwriting occurs. The collector saves declared outputs, scoped WAN/hub/F/policy/intent/rules/connections, both NIC effective-route/effective-NSG views, subnet/table/peering data, hub route tables, defaultRouteTable effective routes and diagnostics/metric definitions. Each Azure call saves `.json`, `.stderr`, `.exit`; partial failures continue and cause exit3. `timing.txt` contains start/completion UTC and shell exit. Exit0 means reads returned successfully, **not** verified routing. Empty results are inconclusive.

**Required separate Firewall onward-route evidence:** use secured-hub > Effective Routes > Azure Firewall and select `hub-firewall`; capture actual routes toward **both** app and backend connections with UTC, selected resource/subscription, prefix, next-hop type/resource and origin. The NIC, defaultRouteTable and Firewall resource views are not interchangeable. The collector creates `firewall-onward-routes-REQUIRED.txt` as an explicit unresolved evidence item. No guessed CLI Firewall type is treated as working. Optional `FIREWALL_ROUTE_RESOURCE_TYPE` accepts an operator-reviewed candidate token, labels the attempt UNVERIFIED, and preserves success/error without establishing route correctness; portal observation remains required when unsupported or inconclusive.

Check connections reflect intent ownership, private policy points to the intended Firewall ID, workload `/0 -> None` remains, no stronger bypass UDR/peering was introduced, and Bastion subnets have no workload route table. The expected private intent association is defaultRouteTable and propagation noneRouteTable; record the actual Azure objects. Do not turn empty/partial responses into `private_routes_verified=true`.

## Demonstration and expected evidence

First preserve local health/routes while both gates remain closed. Then, through a separately reviewed and authorized infrastructure update, set `fixtures_ready=true`, `private_routes_verified=true`, **`test_paths_enabled=true`**, leaving `allow_test_flow=false`. Verify the exact NSG Allow envelope is effective. A baseline timeout while NSGs remain Deny cannot be attributed to Firewall.

On A, each command reserves a new directory automatically under `$HOME/vwan-evidence`:

```bash
vwan-probe closed
```

Expected baseline: attempted tuple/time is preserved, no valid backend response; **matching `AZFWNetworkRule` Deny** under `test-flow`/`app-to-backend-8080` plus healthy local fixture and effective routing are required. A SYN blocked before HTTP cannot carry an HTTP case ID to B.

Next authorize the narrow action change `allow_test_flow=true`, review stable names/tuple and unchanged intent, wait for effective policy, then on A:

```bash
vwan-probe positive
vwan-probe alternate
```

Positive expected: B8080 returns fixture identity and original A IP/ephemeral port; matching Network Allow row and same backend journal case confirm observations. Alternate expected: B8081 remains locally healthy but the exact tuple matches `deny-healthy-alternate`/`deny-app-alt-8081`, Deny. It must not be inferred solely from silence.

On B:

```bash
vwan-probe reverse
```

Expected new B-to-A8082 attempt: locally healthy A8082, exact source/destination evidence and named `deny-reverse-new`/`deny-backend-new-8082` Deny. Established B8080-to-A replies are different state and may succeed without this new-flow allowance.

Optional bounded existing-flow experiment, on A while Allow is effective:

```bash
vwan-probe stream --duration 180
```

After observing valid frames and actual connected tuple, separately close `allow_test_flow=false` and record change start/completion/effect. Azure Firewall documents that Allow-to-Deny changes drop relevant established sessions; do **not** describe this as new-flows-only. No exact propagation timing is guaranteed. The stream has one connection, no retries/reconnect, a five-second socket timeout and total duration+10-second cap. If the control-plane change takes longer than the finite stream, the experiment is inconclusive; a naturally completed stream is not evidence of a bypass. Run a new `closed` attempt after effective Deny and preserve both results. Fresh and held-open flow observations answer different questions.

## Probe files and interpreting outcomes

`vwan-probe closed|positive|alternate|reverse|stream [--out NEW_DIR] [--duration 5..180]` validates source role and local IP before traffic. It opens one numeric TCP socket, binds and fsyncs `connection.json` before SYN with attempted source port, destination and UTC. On connect it adds `connected.json`; HTTP attempt/completion snapshots are separate; frames and final `result.json` retain actual HTTP status, original peer tuple, error and `completed_utc`. Each snapshot is write-once. An explicit OUT must not exist. Use new child paths, not reruns over old evidence.

Every result says **NEEDS_REVIEW**. Exit0 means a bounded attempt and evidence finalization, not a passing network test. Incorrect CLI/config/preflight or evidence errors can be nonzero. Timeouts can come from NSG, route, guest, listener or Firewall. No response, missing backend record, or missing asynchronous logs alone proves inspection. Case ID is HTTP metadata only after connection; correlate denied SYNs by attempted five-tuple/time, not a nonexistent received case header.

Use [queries/network-rule.kql](queries/network-rule.kql) in the correct workspace. Replace all placeholders from the actual `result.json` and outputs, including ephemeral port, actual direction/port, `_ResourceId` and UTC window. Inspect `Action`, `Policy`, `RuleCollectionGroup`, `RuleCollection`, `Rule`; do not invent rows. Extend only enough for ingestion/timestamp uncertainty and re-query deliberately. `AZFWThreatIntel` is optional diagnostic context, not an expected hit. This is network-rule HTTP, not application or NAT logging.

## Rollback and cleanup

1. Preserve fresh results/control snapshots, stop probe processes and stop the three test listeners through each independent Bastion. Inspect only the known lab units; do not kill arbitrary processes. Bounded clients exit on their own, but verify them.
2. Restore `allow_test_flow=false` first through an approved reviewed change; wait for effective Deny and verify new/old test-flow closure. Keep private intent installed.
3. Set **`test_paths_enabled=false`**, review both workload NSGs and verify isolation. NSGs are stateful, so changed rules do not alone prove existing flows are gone. Stop clients/listeners and verify rather than relying on the NSG update acknowledgement.
4. Only then review/authorize destructive removal of the dedicated lab. **Terraform dependencies can remove intent before connections** during inverse destruction. Firewall Deny alone is insufficient once intent is gone. The independent NSG isolation is deliberately required before teardown. Do not use unreviewed targeted deletions to force an assumed safe order.
5. Removing intent can reset propagation to the Default label; it does **not** restore a prior routing design. No live intent-removal bypass variant is provided. A failed/partial removal must be investigated from actual remaining resources, with workload isolation maintained.
6. Verify the resource group, both Bastions/PIPs, Firewall/policy, hub/WAN/connections, VMs/disks, diagnostics/workspace and any cost-bearing leftovers are removed as intended. The resource-group deletion safeguard deliberately refuses unexpected untracked resources. Do not defeat it automatically. Keep the preexisting approved image and SSH keys untouched. Retain/delete state and evidence only under approved retention/security procedures.

For a temporary demo pause, close the Firewall and NSG gates while retaining intent; this is not billing suspension. Stopped VMs alone do not stop Firewall, hub, Bastion, PIP or log charges.

## Costs and limits

Budget for Standard Firewall deployment/data processing, Standard vWAN hub routing infrastructure/connection-related charges, **two Standard Bastions** and their scale units/public IPs, two VMs/OS disks, logging ingestion/retention and applicable network transfer. Routing-intent traffic bypasses the virtual hub router dataplane, so do not double-count its data-processing fee as if it were forwarded there; other hub/service charges remain. Estimate with the actual region/offer in the [Azure calculator](https://azure.microsoft.com/pricing/calculator/), [Virtual WAN pricing](https://azure.microsoft.com/pricing/details/virtual-wan/), [Firewall pricing](https://azure.microsoft.com/pricing/details/azure-firewall/) and [Bastion pricing](https://azure.microsoft.com/pricing/details/azure-bastion/). No current monetary quote or cost cap is asserted.

This is a narrow single-hub/two-spoke source-preservation and private inspection demonstration, not performance, availability, production hardening, state synchronization, routing-intent migration or generic Internet isolation certification. There is no actual test evidence until an authorized operator runs it and completes the results worksheet. See [SOURCES.md](SOURCES.md) for primary documentation and validation scope.
