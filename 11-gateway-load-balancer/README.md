# Scenario11: Gateway Load Balancer with a stateless Linux bridge filter

**Source draft, not a tested deployment or a vendor NGFW.** This independent Terraform root supplies the Azure topology, controlled fixtures, a Linux VXLAN bridge with actual nftables bridge-family filtering, private management and evidence tools. It does not provide IDS/IPS, application inspection, TLS decryption, authentication, conntrack policy, replicated state, automatic failover guarantees or vendor support.

All actual Terraform/provider/Azure/guest datapath outcomes are **NOT RUN**. Terraform/OpenTofu, an initialized provider cache and an HCL parser are absent. Supplied mock-plan tests have not run. Executed Python/shell/source checks, fake commands and guarded-loopback tests are listed in [validation/STATUS.md](validation/STATUS.md); they do not establish working Azure VXLAN. See [results worksheet](RESULTS.template.md), [sources](SOURCES.md), and [full guide](../azure-11-gateway-load-balancer-transparent-chaining-guide.md).

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. No command is executed by opening this README.

## Owned topology and separate decisions

- Dedicated RG `inspection-gwlb`, one approved region/subscription. Provider VNet10.0/16 has NVA subnet10.0.1/24: `nva1`=.4 and `nva2`=.5. Frontend subnet10.0.2/24 contains Gateway LB `inspection-gwlb`, frontend `inspection-frontend`, F=10.0.2.10. `nva-pool` has exactly those two NICs.
- Gateway pool pairs Internal VXLAN VNI800/UDP10800 with External VNI801/UDP10801. HA rule `ha-ports` is All/0/0, **floating_ip_enabled=false**, outbound SNAT disabled. Do not copy scenario06's Floating-IP rule.
- Consumer VNet10.20/16, workload10.20.1/24, private backend `app` B=10.20.1.20. Standard Regional `public-lb` has actual allocated public P on `public-frontend`, with `http-8080` and `http-8081` mapping the same frontend/backend ports to `app-pool`. Both rules are nonfloating and disable outbound SNAT. No outbound rule or NAT gateway is supplied.
- `enable_chain` attaches the consumer frontend to the **GWLB frontend configuration resource ID**. F is not a UDR next hop. There is no inspection UDR, default blackhole, provider-consumer peering, public VM NIC or extra public client VM.
- Management VNet10.40/16 hosts one Standard `management-bastion` in10.40.2/26. Only management↔provider and management↔consumer peerings exist, without gateway transit, remote gateways or forwarded traffic. Bastion has its own Standard public HTTPS service IP; native SSH targets stay private. It is not Premium private-only Bastion.
- An independently approved external client supplies actual stable global C/32. It cannot be a consumer backend. This package does not authorize using the assistant host or an arbitrary third-party client. A client behind NAT must record its local tuple and externally translated C:c separately. C/32 is an address restriction, not user authentication; other clients sharing that NAT address may match it. Both endpoints use plain HTTP and synthetic content only, never credentials or private data.

Consumer frontend/rule selection, GWLB healthy-NVA selection and consumer backend selection are different platform decisions. The Linux bridge does not route the inner IP packet, terminate HTTP/TLS, or translate addresses. GWLB affinity is not state replication.

## Tuple boundary and actual stateless filtering

Public client: `C:c -> P:8080`. Backend socket should observe `C:c -> B:8080`, allowing for a client-side NAT port when the local socket is different. At the NVA, the actual inner destination and reverse source relative to consumer translation remain **capture-required**. Do not invent an NVA SNAT/DNAT or an exact reverse conntrack tuple.

Owned devices are non-addressed `gwlb-br0`, `gwlb-ext`(801/10801), and `gwlb-int`(800/10800). Only those VXLAN devices join the bridge. The ordinary NIC remains outside it. Its MTU is1550; bridge/tunnels are1500. Azure NVA NIC forwarding is enabled. Guest global ip_forward/rp_filter and bridge-netfilter sysctls are deliberately untouched: this is L2 bridge-port forwarding, not a routed Linux firewall.

Dedicated table `bridge azure_gwlb_lab` scopes rules to the owned ports, preserving other tables/bridges. Closed mode drops owned transit. The acknowledged primary mode permits only:

- External→Internal: sourceC, destination in the exact candidate set{P,B}, IPv4TCP destination8080.
- Internal→External: source in{P,B}, destinationC, IPv4TCP source8080.
- Both8081 directions have named Deny counters. All other owned traffic, IPv6 and non-IP frames are dropped. No broad Internet, ARP/ND forwarding or host-facing owned-port path is allowed.

The two-address candidate set is an explicit **initial investigation bound**, not proof which address is seen at either tunnel. If captures show another tuple, the lab is BLOCKED pending reviewed redesign; do not widen it silently. This stateless filter does not validate TCP handshakes, application content or connection ownership.

`allow-primary` is **persistent until an explicit close/reconciliation/boot action**; there is no automatic expiry. `withdraw` changes health advertisement, not the Allow policy or established flow termination. Every close/Allow transition withdraws health, so explicitly advertise again only after reviewing stable local state. Finite client probes do not close the firewall for you.

## NSGs and six false gates

- App priority100 `test-client-ingress`: conditional Deny/Allow, C/32→B/32 TCP8080/8081. Both comparison ports must be open here before attributing a negative to the bridge.
- All VM NICs110 `management-ssh`: management10.40.2/26→own privateIP TCP22.
- All VM NICs120 `platform-readiness`: AzureLoadBalancer→own privateIP TCP8008(NVA) or8009(app).
- NVA130 `vxlan-inbound`/`vxlan-outbound`: UDP10800/10801 between own privateIP and the initial bounded provider10.0/16 transport envelope. This is **not proof of the platform's actual outer source**; capture and verify it. It is not Internet-wide UDP. If the supported platform requires another envelope, stop for a scoped reviewed correction.
- All VM NICs200 deny AzurePlatformDNS;4000 deny other inbound/new outbound. Workload subnets explicitly disable default outbound access. Established permitted replies and Azure platform services have their own semantics; these settings do not create a default route or prove arbitrary egress impossible.
- Bastion's separate mandatory service rules support its control/management channel, not application egress.

`deploy_lab`, `image_prerequisites_confirmed`, `appliances_ready`, `application_ready`, `enable_chain`, `test_paths_enabled` all default false. Deployment needs the image attestation. Chain activation needs both historical readiness attestations. Opening test ingress requires the chain and both readiness attestations. These booleans are not permissions, live health observations or guaranteed ordering barriers.

No tuple-verification gate creates a circular prerequisite. Under a closed bridge, the exact test NSG can be opened to obtain incoming SYN/outer evidence. Actual return capture then needs the separately acknowledged narrow8080 opening, followed by explicit closure and review.

## Prerequisites, cost and sensitive data

Use an approved disposable Azure public-cloud subscription/region with current Gateway LB eligibility, VM/Bastion capacity, quotas, registered providers and a cost budget. Current provider Gateway documentation includes feature/support eligibility cautions; independently verify current subscription support. This module does not register features/providers or expand permissions.

Supply an approved existing same-subscription **versioned Compute Gallery image**, not latest. It must already contain Python3, iproute2 with VXLAN/bridge support, kernel/nftables bridge-family support, tcpdump, SSH, cloud-init, systemd and a functioning Azure guest agent. It must support underlay1550 and inner1500, no conflicting host policy or automatic bootstrap downloads. Verify these capabilities on a separately authorized image workflow. No package install, image build, Docker pull, kernel module installation or public bootstrap egress is supplied. There is no vendor image/license.

Use an existing approved SSH public key. Never put private keys, passwords, secrets, tokens or license data in Terraform, cloud-init, tags, config JSON or this directory. AzureRM5.12.0 and Terraform>=1.9,<2 are declared; the genuine provider lock is absent because initialization was not run. Provider schema, service acceptance, mock-plan execution and rendered cloud-init still need validation. Compressed `gz+b64` write_files reduce source size, but source estimates are not actual Terraform rendering.

Protect state/plans/tfvars/logs/captures as confidential with approved encrypted storage and access controls. No backend is created. Azure CLI `--query` is client-side filtering, not server-side minimization. Declared outputs, metadata/tags and errors are not automatically redacted. PCAP snaplen256 and HTTP body prefixes can retain sensitive data. Use synthetic traffic; privately review and redact an approved copy before sharing. No automatic upload is performed.

Budget two LBs and their data processing, three VMs/disks, one Standard Bastion, two owned Standard public IPs, peering/data transfer and evidence storage. Closing a rule or stopping VMs does not stop all charges. Use actual approved region/SKU and the [Azure calculator](https://azure.microsoft.com/pricing/calculator/). No price or tested capacity is asserted. Unzoned defaults make no availability-zone resilience claim.

## Future setup after separate authorization

No provisioning, guest mutation or teardown is run by this draft creation. Review the whole flow before future execution.

```bash
cp terraform.tfvars.example terraform.tfvars
# Replace placeholders and retain all six false gates initially.
./scripts/check-local.sh
```

After approved tool/provider setup, preparatory validation is:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

Init can download provider code and was not performed here. Supplied tests are plan-only mocks, not Azure checks. Review a real plan, genuine lock, current costs, image and rendered custom-data before any authorized deployment. This README intentionally contains no apply/destroy command.

1. Set only deploy_lab and image_prerequisites_confirmed after image/permission/cost review. The public consumer exists but remains unchained with test NSG Deny. All guest images start from closed/withdrawn NVA state.
2. Use independent Bastion management, verify app fixtures and both local NVA controllers. Do not treat successful cloud-init provisioning as datapath proof.
3. On each NVA, review the exact guest action and node before running:

```bash
sudo gwlb-control status
sudo gwlb-control prepare --confirm-guest-change
sudo gwlb-control advertise --confirm-guest-change
sudo gwlb-control status
```

Prepare verifies ownership, saves original underlay MTU, installs closed bridge-family policy before bringing owned ports up, and leaves health withdrawn. Advertise is a separate action after local structure checks. On app:

```bash
gwlb-app-ready
```

Both `azure-gwlb-fixture@8080.service` and `@8081.service` bind B; `azure-gwlb-app-health.service` HTTP8009 verifies both through synthetic source-bound local requests. NVA HTTP8008/health checks fresh<=6second local topology/link/MTU/policy state and advertisement, refreshed every2seconds. Closed policy can be healthy. Neither health endpoint proves end-to-end VXLAN, correct outer NSGs, Azure eligibility or application policy.

4. Verify actual independent LB probe histories and local state. Attest appliances_ready/application_ready, then separately authorize enable_chain. Verify the consumer frontend's exact GWLB frontend ID before opening tests.
5. Open test_paths_enabled only after chain/readiness review. Keep the guest bridge closed for initial captures. Observe effective NSGs/routes and rule counters. Do not assume an NSG update terminates an already-established flow.

## Private management and public client configuration

The operator helpers match the explicit subscription and exact owned LB/frontend/pool/publicIP/Bastion IDs, all VM/NIC/VNet maps and probe IDs before Azure reads. They do not prove authorization or runtime reachability. Existing authentication is required; automatic extension installation is disabled.

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
source ./scripts/common.sh
load_context
require_extensions bastion
: "${SSH_PRIVATE_KEY_FILE:?Set existing approved local SSH private key path}"
az_read network bastion ssh -g "$RG" -n management-bastion \
  --target-resource-id "$(read_map_output vm_ids nva1)" --auth-type ssh-key \
  --username "$(read_output admin_username)" --ssh-key "$SSH_PRIVATE_KEY_FILE"
```

Use nva2 or app in the VM map for the other targets. Preserve host-key checking. No private key is copied to guests.

Create a new public config locally and transfer it only through a separately approved path to the authorized external client. It contains exactly client_public_ip,consumer_public_ip,backend_ip. No transfer or probe happens in this helper:

```bash
: "${CLIENT_CONFIG:?Set a NEW local JSON filename}"
./scripts/make-client-config.sh "$CLIENT_CONFIG"
```

On that external client, use the package's scripts/gwlb-probe or its approved installed copy. Supply an actual local bind address belonging to that host; the helper does not discover publicC through a third-party service. If behind NAT, capture/record the mapping separately. A C/P change invalidates earlier evidence and may replace NVA custom-data/VMs; close tests and review the entire plan before changing it.

## Evidence and exact demonstrations

```bash
./scripts/collect-control-plane.sh
```

Optional OUT must be nonexistent. Each read retains private `.json/.stderr/.exit`, start/completion UTC and shell exit. Exit3 denotes failed reads; exit0 is collection only. Actual chain/policy verification remains NOT_PERFORMED. The collector saves both LB configurations, independent probe definitions, current metric definitions, NIC effective routes/NSGs, VNet/peering state and public mapping. Inspect actual per-backend DipAvailability histories separately from frontend VipAvailability; aggregate health is not per-flow evidence. CLI response and metric behavior remain unvalidated.

On each NVA, record snapshots and bounded captures:

```bash
sudo gwlb-evidence
sudo gwlb-evidence --capture --seconds 10 --packets 200 --acknowledge-sensitive-capture
```

Each helper creates a new private directory. Captures use verified underlay plus gwlb-ext/gwlb-int, max60seconds and1000packets per interface, snaplen256. Outer filter is own privateIP plus UDP10800/10801, not an assumed remoteF source. Inner filters include only C↔{P,B},TCP8080/8081. If inner captures are empty but outer packets arrive, decode bounded outer VXLAN headers to investigate actual inner addresses/VNIs before declaring no traffic or widening policy. Retain per-interface stderr/return codes; short/failed capture is incomplete evidence.

1. **Closed8080:** while both NVAs are closed/advertised and the exact app NSG is open, capture both and run one finite external attempt:

```bash
: "${CLIENT_CONFIG:?Set reviewed public config}"
: "${LOCAL_SOURCE_IP:?Set actual local IPv4 on the authorized external client}"
./scripts/gwlb-probe closed --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
```

Require the fresh original tuple/time, selected NVA outer/inner ingress and the matching named closed8080 counter increment, with healthy app fixtures. An HTTP case cannot reach the backend when a SYN is dropped. Timeout alone does not establish policy enforcement.

2. **Primary8080 and initial return boundary:** on BOTH NVAs, explicitly acknowledge the candidate tuple envelope, then separately advertise:

```bash
sudo gwlb-control allow-primary --confirm-guest-change --acknowledge-capture-required
sudo gwlb-control advertise --confirm-guest-change
```

These actions do not expire automatically. The **first opening is only for one finite positive and its bounded forward/return captures** within the approved observation window. Do not run alternate, payload, stream or health-withdrawal controls before this first closure and tuple review.

```bash
./scripts/gwlb-probe positive --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
```

After the bounded captures finish and release their locks, explicitly close **BOTH NVAs**, each in its own verified management session:

```bash
sudo gwlb-control close --confirm-guest-change
sudo gwlb-control status
```

Verify current closed/withdrawn state, ended flow and each command's result. Review the full marker azure-gwlb-fixture-v1/case/identity evidence, actual B socket and both-direction same-NVA captures. Record actual inner P/B and outer/VNI boundaries rather than filling expected addresses automatically. If the candidate envelope or return ownership is unresolved, stop closed; do not continue broader controls or silently widen policy.

**Only after that review and separate authorization**, re-open primary on BOTH NVAs and separately advertise stable state:

```bash
sudo gwlb-control allow-primary --confirm-guest-change --acknowledge-capture-required
sudo gwlb-control advertise --confirm-guest-change
```

Then run the broader finite controls, with fresh evidence/captures:

```bash
./scripts/gwlb-probe positive --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
./scripts/gwlb-probe alternate --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP"
./scripts/gwlb-probe payload --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP" --bytes 262144
```

Alternate8081 needs its listener/application health independently ready and the named8081 Deny counter on the selected NVA. Payload verifies exact size/hash of a controlled TCP transfer; it is not proof of packet size, no fragmentation, MSS or PMTU. Capture those details separately, then close both nodes again unless proceeding directly into the separately authorized closure experiment below. Finite probes never close the persistent Allow automatically.

3. **Closure and old/new flows:** optionally start one finite stream5..180seconds, identify its actual NVA by evidence, then close the policy on both NVAs and separately attempt a new closed probe:

```bash
./scripts/gwlb-probe stream --config "$CLIENT_CONFIG" --source-ip "$LOCAL_SOURCE_IP" --duration 60
# In the separately authorized NVA sessions, close each exact node:
sudo gwlb-control close --confirm-guest-change
```

One socket, no reconnect/retry,5second socket timeout and finite overall cap. Observe the old stream separately from the new connection. Close withdraws health; advertise closed mode again only when continuing closed-policy experiments. No seamless-session or fixed convergence claim is made.

4. **Single-node health withdrawal:** this is a separate experiment. Re-establish the reviewed primary-Allow/advertised baseline on BOTH NVAs using step2, then start a fresh finite stream. Do not reuse the closed/withdrawn state from step3. Only after identifying the old flow's owner and verifying the OTHER NVA healthy, run on that one node:

```bash
sudo gwlb-control withdraw-health --seconds 30 --confirm-guest-change
```

This preserves its current nft policy/links while health is withheld for5..120seconds. Normal completion re-advertises only after local restoration checks. Track new flows versus the old stream independently. It is not a VM crash, policy Deny, conntrack-loss or all-backends-down experiment. On handled interruption or error, best-effort safe closure may replace restoration and requires reconciliation; inspect the actual recorded outcome.

Control operations and evidence capture share an exclusive lock held for the whole bounded operation/restoration. Concurrent close/withdraw/capture cannot override it. Status is not a lock-release check. Finish or interrupt the exact helper, inspect process exit/events and pending state, then close. Never delete a lock file or kill unrelated processes. Capture before/after on that NVA or on the other NVA during withdrawal; do not promise simultaneous same-node helper capture.

The external probe CLI is `gwlb-probe closed|positive|alternate|stream|payload --config PUBLIC_JSON --source-ip LOCAL_IP [--out NEW_DIR] [--duration 5..180] [--bytes 1..262144]`. Existing paths/symlinks are refused. Evidence includes pre-SYN connection.json, connected/request stages when reached, response headers, bounded8192byte body prefix, frames and result.json with completion UTC. Every result is **NEEDS_REVIEW**. HTTP200, probe health or fixture identity alone does not establish the inspection path.

## Recovery, isolation before detachment, cleanup

The controller records pending/uncertain transitions before guest mutation, with persistent per-attempt events/snapshots. Status is recorded intent plus local observations, not Azure health or packet proof. Success bookkeeping snapshots/events are explicitly taken before pending-marker removal; verify a subsequent status and /health separately. If unlink succeeded but storage finalization/rewrites fail, marker survival cannot be guaranteed. Preserve stderr and investigate before further actions. Partial changes, disk/write failures, SIGKILL and power loss can leave unresolved state; do not claim rollback always succeeds. After lock release, inspect the exact node and use `reconcile --confirm-guest-change` or `recover --confirm-guest-change` to re-create closed/withdrawn owned state. Neither restores Allow automatically. Review before separately advertising/reopening. Boot closes/withdraws rather than resuming Allow; prior interruption markers still require reconciliation.

1. Stop finite external clients. Close exact policies on both NVAs; verify new/old traffic isolation, pending state and records.
2. Stop both app fixture units via independent management. In a fresh private shell log, verify systemctl queries succeeded and show inactive, and ss succeeded with no8080/8081 listeners. Do not treat a failed query as empty. Keep app health/management long enough to inspect state.
For the app service-stop verification, after authorizing that exact cleanup action:

```bash
sudo systemctl stop azure-gwlb-fixture@8080.service azure-gwlb-fixture@8081.service
for unit in azure-gwlb-fixture@8080.service azure-gwlb-fixture@8081.service; do
  state=$(sudo systemctl show "$unit" --property=ActiveState --value) || exit 1
  [[ "$state" == inactive ]] || { printf 'Still active or uncertain: %s\n' "$unit" >&2; exit 1; }
done
listeners=$(sudo ss -H -ltn '( sport = :8080 or sport = :8081 )') || exit 1
[[ -z "$listeners" ]] || { printf 'A test listener remains.\n' >&2; exit 1; }
```

3. Separately close test_paths_enabled and verify actual NSG state plus ended flows. NSGs are stateful; a new Deny alone is insufficient evidence of old-flow isolation.
4. Only after endpoint/service isolation, separately authorize enable_chain=false or removing consumer rules. **Detaching an open public consumer creates an inspection bypass.** A single plan that changes NSG and chain does not guarantee safe execution order; use staged verified isolation.
5. `restore-original --confirm-guest-change` removes only owned bridge/tunnels/table and restores only the recorded underlay MTU after ownership checks. It does not restore arbitrary prior Azure associations or unrelated rules/sysctls. Pending/uncertain records block unsafe reopening; ambiguous ownership requires operator investigation. A restored state remains removed/withdrawn across boot until explicit prepare.
6. Review/authorize removal of the owned consumer, GWLB, three VMs/disks, three VNets/peerings, Bastion and two public IPs in dependency-aware order. No external/shared resource should be deleted. Keep management until isolation is proven; respect the RG safeguard. Review residual billing and approved private state/evidence retention. Existing image/SSH keys remain untouched.

TLS, vendor appliances, outbound-initiated chaining, NIC-public-IP consumer variant, cross-tenant/cross-subscription chaining, cross-zone failover and all-backends-down experiments are not implemented. A draft that parses or passes fake-command tests is not deployment-ready without genuine provider validation and separately authorized runtime evidence.
