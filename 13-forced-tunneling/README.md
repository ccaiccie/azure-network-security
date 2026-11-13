# Scenario 13: forced next-hop inspection through a peered Linux perimeter

**Source draft, not a deployed or runtime-validated lab.** This owns an Azure Firewall, a Linux forwarding/SNAT appliance and a controlled public HTTP origin. It demonstrates a routed **Azure VNet-peering perimeter simulator**, not an on-premises site, VPN tunnel, BGP default, VPN Default Site, ExpressRoute or FastPath. It does not implement vendor NGFW features, HA or replicated connection state. See [the full scenario guide](../azure-13-forced-tunneling-perimeter-inspection-guide.md), [results](RESULTS.md), [sources](SOURCES.md) and [validation status](STATUS.md).

All deployment and exposure switches default false. We have not authenticated to Azure, initialized a provider, generated/read/transmitted keys, deployed resources or run guest/kernel commands. The runnable configuration still needs an approved prebuilt image and region, operator review and separately authorized deployment. Do not call it a self-contained image build or a proven Azure path.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. Opening these files executes nothing.

## 1. Owned topology and routing

The default new resource group is `inspection-forced`. One region contains:

| Role | Address/resource | Purpose |
|---|---|---|
| Hub | `hub`, 10.0.0.0/16 | Firewall transit only |
| Firewall data | AzureFirewallSubnet 10.0.1.0/26; allocated **F** | `hub-firewall`, Standard, policy `forced-policy`; no tenant data public IP |
| Firewall management | AzureFirewallManagementSubnet 10.0.2.0/26; own management public IP | Azure service operations, never user-flow egress |
| Client A | `app`, 10.20.0.0/16; workload10.20.1.0/24; VM10.20.1.10 | No public IP, no listener |
| Perimeter E | `perimeter`, 10.30.0.0/16; workload10.30.1.0/24; VM10.30.1.4 | One forwarding NIC with public IP **P**, owned nftables table |
| Origin B | `origin`, 10.50.0.0/16; workload10.50.1.0/24; VM10.50.1.20 | Public IP **D**, synthetic listeners8080/8081/8082 |
| Management | `management`, 10.40.0.0/16; AzureBastionSubnet10.40.2.0/26 | One Standard `management-bastion`, independent peerings |

F, P and D are actual allocated output values. Never replace them with documentation addresses or assume F ends in .4. Four owned public IPs are P, D, Firewall management and Bastion. Only the perimeter NIC has Azure IP forwarding enabled. All workload subnets disable implicit default outbound access. Explicit public-IP return/egress remains intentional on E and B.

Hub↔app and hub↔perimeter are four directed peerings allowing forwarded traffic. Management has ordinary directed peerings to each of the other four VNets, with no forwarded traffic, gateway transit or remote gateway. There is no direct app↔perimeter peering and no hub↔origin peering. Management return10.40/16 wins over inspection defaults. Verify actual private SSH access before every experiment; topology alone is not observation.

| Table/subnet | Exact UDR | Propagation |
|---|---|---|
| `app-forced-default` / app workload |0/0→VirtualAppliance F | Disabled |
| `firewall-to-perimeter` / Firewall data |0/0→VirtualAppliance E | Disabled |
| `perimeter-return` / perimeter workload |10.20.0.0/16→VirtualAppliance F | Disabled |

The perimeter retains its system Internet default, so it does not loop public D back toward F. Firewall returns to app on the more-specific hub/app peering route. Origin and management have no customer route tables. **No customer table or NSG is attached to AzureFirewallManagementSubnet.** Microsoft supplies its Internet management default with propagation disabled. These management and data defaults are distinct.

## 2. Source ownership and two implemented modes

`source_mode="preserve"` is the baseline. Firewall policy private ranges0/0 suppress network-rule SNAT to D. E should receive the original A:a→D:d. Perimeter guest SNAT creates private E:e→D:d; Azure maps E:e to public P:p. Origin's public D:d maps separately to B:d. B reports observed P:p, never private E. Correlate captures, conntrack and logs; no port is assumed preserved.

`source_mode="firewall_private"` requires `snat_comparison_acknowledged=true`. Policy `IANAPrivateRanges` permits Firewall private SNAT for public D, so E should receive actual S:s→D:d, with S in10.0.1.0/26. S need not equal F. Perimeter guest policy and NSGs select **that mode's prefix only**, not a union. The reverse packet after guest reverse-SNAT goes to A through10.20/16→F in preserve mode, or S through hub10.0/16 peering in private mode. Firewall reverses its own translation separately.

Source-mode/config/P/D/F changes can alter VM custom-data and cause VM replacement. Never switch while clients/listeners/exposure are open. Close and verify isolation, review the entire replacement plan, retain independent management, then repeat all readiness and tuple evidence. No automatic safe live mode migration is promised. Azure-hosted public-IP traffic may remain on the Microsoft backbone; this is not proof of a physical ISP hop.

## 3. Exact two-stage policy and NSGs

Firewall group `forced-rules` priority200 contains network collections:
- `deny-azure-negative` priority100, Deny, rule `deny-app-8081`: A/32→D TCP8081.
- `test-flow` priority200, gated Deny/Allow, rule `app-to-controlled-origin`: A/32→D TCP8080 and8082.

No application, DNAT, TLS, parent-policy or broad Internet Allow is supplied. Threat intelligence is Alert. Guest table `inet azure_forced_lab` uses a drop forward policy, strict SYN-only NEW admission, established replies, exact interface/source/D/ports, and scoped SNAT to E. Guest allows8080/8081 only when explicitly opened; named `deny-perimeter-8082-forward` and reverse drops always deny8082. Closed policy names the8080/8081 drop counters. No global nftables flush or conntrack flush is performed. This is a narrow Linux stateful teaching filter, not an NGFW.

NSGs independently default Deny:
- App100 outbound A/32→D/32 all three test ports.
- Perimeter100 inbound mode prefix→D/32 all test ports;101 outbound E/32→D/32 all test ports;102 outbound D/32 with test source ports→mode prefix and ephemeral destination ports. Return D→E relies on established NSG flow state.
- Origin100 inbound P/32→B/32 all test ports.
- All three VMs110 inbound SSH only from10.40.2.0/26,200 outbound AzurePlatformDNS Deny,4000 other inbound/outbound Deny. Bastion has its separate mandatory service NSG rules.

The P/32 origin envelope identifies this perimeter public address, not A or a particular application identity. A timeout is never proof of which layer denied a flow. Open exact NSG envelopes before attributing a failure to either inspection stage, and verify all three local origin listeners first. NSG existing-flow state can persist after edits. Firewall Allow→Deny can drop relevant existing sessions once effective; measure held-open and fresh flows separately, without assuming instantaneous control-plane timing.

## 4. Prerequisites, costs and secrets

Required operator inputs: approved subscription UUID, available region, existing public SSH key, approved same-subscription Compute Gallery **image version** ID, permissions/quota/budget and explicit approval for resources and later guest changes. The image must already contain Python3, iproute2, systemd/cloud-init/SSH, nftables supporting inet NAT, conntrack and tcpdump; kernel conntrack/NAT support must be available at boot. In particular, enrollment reads net.netfilter.nf_conntrack_tcp_loose before the first nft rule, so that sysctl must already exist on a clean boot through an explicitly approved image/module-load configuration. Preinstalled userspace tools alone do not prove this. The helper does not silently load modules; a missing sysctl stops preparation without declaring readiness. It must start with IPv4 forwarding disabled and no conflicting forwarding/security policy, competing NAT, agent or service. Verify image capabilities and baseline sysctls under its normal approved build process. No package download or image build is included, and the workload NSGs deliberately prevent general DNS/package egress.

Use Terraform>=1.9,<2 and the pinned AzureRM5.12.0, plus an approved Azure CLI and already-installed Bastion extension for private SSH. No provider lock file is fabricated; create/review a lock with verified provider packages in the authorized preparation environment. Our pinned5.12 documentation fetch failed; current official docs informed the draft but do not validate that pinned schema. `fmt`, initialization, validation, mock plans and actual Azure creation remain NOT RUN here.

As checked **4 November2026**, Microsoft's [capacity table](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues) blocks new Standard Firewalls in East US and lists other regional/zonal constraints. `location` has no default; recheck capacity before choosing it. Do not silently substitute a region.

Costs include continuous Standard Firewall, one Standard Bastion, three VMs/disks, four Standard public IPs, Log Analytics ingestion/retention, peering and transfer, plus the prerequisite image. A quiet or closed lab still costs money. Consult the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for the actual subscription/region/time and budget before deployment; no live price was quoted. This is not a production HA design.

No VPN PSK, CA/private key, password or secret is generated or used by this source. Existing public-key input is public material only. Terraform state/plan can nevertheless contain **Log Analytics primary/secondary shared keys exported by the provider**, even with workspace local authentication disabled. Treat state, plans, caches, declared outputs and logs as private. Tags are operator-entered free text, not automatically redacted. CLI `--query` is client-side filtering after response receipt, not a secrecy boundary. Packet captures and fixture bodies may expose traffic. Never put real customer data or credentials into synthetic HTTP. Share only a reviewed sanitized copy.

## 5. Preparation and staged authorization

Review the entire source, then copy the public example and fill the required nonsecret inputs. Invalid placeholders intentionally prevent deployment. All nine booleans default false:
`deploy_lab`, `image_prerequisites_confirmed`, `fixtures_ready`, `private_routes_verified`, `perimeter_ready`, `origin_access_enabled`, `test_paths_enabled`, `allow_test_flow`, `snat_comparison_acknowledged`.

Attestations record historical checks; they are not permission, real-time health or automatically discovered proof. Setting `deploy_lab=false` after deployment requests destruction, not pause. Leave it true while closing policies and retaining management/routes for inspection.

Safe local source checks:
```bash
bash scripts/check-local.sh
```

In a separately approved preparation environment with reviewed provider cache, the operator may run formatting/schema checks and the **mock-provider plan-only** tests. Never replace the mock provider with a live one to claim safe tests. These commands were not run here:
```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```
Initialization can download provider code and create local files, so review sources/lock and follow local installation permissions. A real plan is separate, may call Azure and is not part of the offline suite. No apply or destroy command is included in this runbook. Review and authorize such operations separately.

After authorized substrate creation with only deployment/image gates true, keep all exposure/policy gates false. Cloud-init starts origin fixtures, verifies local client readiness, and enables `forced-prepare.service`. Perimeter boot enrollment installs a **closed** owned table before enabling ip_forward=1 and sets owned rp_filter/redirect/source-route controls and tcp_loose=0. This is local preparation, not Internet access. Inspect cloud-init/service logs and service startup; no readiness claim follows merely from provisioning completion.

## 6. Private management and local readiness

All following Azure/guest commands are **future operator actions**, not executed evidence. First load the strict identity guard and ensure the Bastion extension is already approved/installed; automatic extension installation is disabled:
```bash
export SUBSCRIPTION_ID="REPLACE_WITH_APPROVED_UUID"
source scripts/common.sh
load_context
az extension show --name bastion --query name -o tsv
```

Use existing approved private key through the authorized SSH workflow, never paste it into chat, state or this folder. Native Bastion SSH targets the verified VM ID:
```bash
: "${EXISTING_SSH_KEY_PATH:?Set approved local private-key file path}"
az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name "$(read_output bastion_name)" \
  --target-resource-id "$(read_map_output vm_ids app)" \
  --auth-type ssh-key --username labadmin --ssh-key "$EXISTING_SSH_KEY_PATH"
```
Repeat with `perimeter`/`origin`; use the configured username if changed. Verify host keys through the approved process, not by disabling checking. Bastion public access, region availability and actual peering SSH still require runtime validation.

On A and B, run `forced-ready`. A must report LOCAL_CLIENT_READY and no active fixture unit. B must report LOCAL_FIXTURES_READY after all exact units8080/8081/8082 and actual bound local HTTP responses pass. The fixture service allows AF_NETLINK for its read-only `ip` NIC check, while keeping capability sets empty. It avoids reverse DNS; explicit literal IP probes do not need DNS. Marker is `azure-forced-origin-v1`, with case, UTC, socket peer and server fields.

On E:
```bash
sudo forced-control status
sudo systemctl status forced-prepare.service --no-pager
```
Read status as recorded intent plus local owned-table/sysctl observations, not proof of Azure routes, NAT or forwarding. Confirm current closed table, expected interface/config, no uncertain transition and the intended image baseline. If an earlier operation failed, reconcile only after investigating it:
```bash
sudo forced-control reconcile --confirm-guest-change
sudo forced-control status
```
`prepare`, `reconcile` and `recover` always establish closed state, never reopen. `close` keeps any prior uncertainty record until explicit reconciliation. Unverified ownership prevents emergency kernel mutation. `restore-original` is only for already closed and independently isolated guest rollback; it restores captured owned sysctls and deletes only the owned table, leaving other rules untouched. ip_forward is changed first because it can reset other IPv4 defaults, then captured values are restored and checked.

## 7. Route evidence and opening sequence

Collect a new private configuration snapshot from the approved operator terminal:
```bash
RUN=$(mktemp -d -t forced-review-XXXXXXXX)
bash scripts/collect-control-plane.sh "$RUN/control"
```
The final output path must not already exist, even empty; reruns never overwrite it. Every Azure read has the explicit subscription. All VM/NIC/VNet/route/PIP/Bastion IDs are validated against exact names and the same RG/subscription before reads. The collector preserves JSON/stderr/exit results, PRIVATE-HANDLING-REQUIRED.txt, summary and UTC start/end. It never marks an empty successful result as route proof and never reads VPN/key/VM bootstrap endpoints. It uses no extension auto-install.

Required inspection: A's actual effective default to F; Firewall data association/default to E; E's actual return10.20/16→F, hub route to S, Internet default; ordinary management return; source-mode policy and NIC forwarding; exact NSGs and P/D associations. Firewall service-hidden NIC effective routes are not invented; combine its subnet/table/peering config with real packet/log evidence. Guest `ip route get` shows the guest FIB, not Azure SDN UDR decisions.

After verifying local fixtures, closed perimeter and private routes, record the three readiness gates true. Open `origin_access_enabled`, then `test_paths_enabled`, while leaving `allow_test_flow=false` and guest closed. Review each staged plan and authorized change. Fresh `forced-probe closed` should correlate to named Firewall Deny, not a silent NSG block. Then set only `allow_test_flow=true`; with guest still closed, a fresh8080 case should show Firewall Allow plus named guest closed drop. This separates the two controls without claiming path from a timeout.

Next explicitly open E for the reviewed mode and D only:
```bash
sudo forced-control allow-test --confirm-guest-change --acknowledge-reviewed-scope
sudo forced-control status
```
This Allow persists until close, failure recovery or reboot. There is no automatic expiry. Obtain the first finite positive and mode-labelled captures. Let the bounded capture finish, verify its process has exited and the shared control/evidence lock is released, then explicitly close E and verify its current owned drop policy. Restore the Azure Firewall test-flow network collection to Deny by setting allow_test_flow=false in a separately reviewed authorized update, and verify a fresh named Azure Deny. Only then review all translations before a separately authorized broader reopening of both required inspection controls. A concurrent close cannot preempt the capture lock. Do not infer success from a saved state or completed update alone.

## 8. Exact positive, negative and long-lived demonstrations

On A, each helper call uses one numeric destination, one bound client socket, a unique case and a new private evidence directory. `--out` must be nonexistent; omit it for a unique default. No automatic retry/reconnect, redirect, proxy or TLS is involved. This is plain HTTP, not HTTPS.
```bash
RUN=$(mktemp -d -t forced-cases-XXXXXXXX)
forced-probe positive --out "$RUN/positive"
forced-probe alternate --out "$RUN/azure-deny-8081"
forced-probe perimeter --out "$RUN/perimeter-deny-8082"
```
Run the broader controls only after the first positive/capture review and a separately reviewed reopening. Client records runtime-config.json, result.json with attempted_local/destination before connect, start/completion UTC and connect/request status, plus received response/frames. A blocked SYN has no HTTP case ID at the denying device: correlate tuple/time/counters, not a nonexistent HTTP header. Negative helper completion/NEEDS_REVIEW is not a Deny verdict.

| Case | Required result evidence, not observed here |
|---|---|
| Firewall closed,8080 | Healthy B; exact NSGs open; AZFWNetworkRule Deny `app-to-controlled-origin`; no positive response |
| Firewall open, guest closed,8080 | Firewall Allow; E sees current A/S tuple; named guest closed counter increases; no origin receipt |
| Both open,8080 | Firewall Allow; exact mode source at E; scoped guest SNAT/conntrack; B reports P:p and matching marker/case; complete finite response |
|8081 alternate | Healthy B8081; named Firewall Deny `deny-app-8081`; no requirement for E/origin HTTP receipt |
|8082 perimeter negative | Healthy B8082; Firewall Allow; E named8082 drop counter/packet evidence; no origin receipt |
| Restore closed | Explicit guest closure and Firewall Deny effective; fresh case denied with attribution; held-open flow measured separately |

On E, bounded evidence snapshots/capture are explicit and private:
```bash
sudo forced-evidence
sudo forced-evidence --capture --seconds 15 --packets 200 --acknowledge-sensitive-capture
```
It writes a unique `/var/lib/azure-forced-lab/evidence/capture-*` directory with before/after snapshots, read-results.json, capture-result.json, optional perimeter.pcap and tcpdump stdout/stderr. The filter matches **D and the three test ports**, without restricting presumed A/S, so unexpected source behavior remains visible. Snaplen256 and packet/time caps do not make payload non-sensitive. Conntrack reads are scoped to D/TCP, timeout bounded, with retained stdout64KiB/stderr8KiB caps; truncation is explicit and incomplete. Inspect both pre/post-NAT packet shapes and conntrack; E's guest capture alone cannot reveal the later Azure public P mapping. Match B's socket evidence. Collect fresh AZFWNetworkRule rows with `queries/network-rule.kql` and origin journals for the same bounded UTC/case window.

Long-lived single-flow observation on A:
```bash
forced-probe stream --duration 90 --out "$RUN/stream"
```
In another authorized E session, after saving an open baseline:
```bash
sudo forced-control fail-forwarding --seconds 30 --confirm-guest-change
```
Allowed duration is5..120 seconds. The controller closes its table, holds the exclusive lock, retains conntrack, waits, checks closed local state, then normally restores the prior open table. Handled HUP/INT/TERM instead leaves best-effort closed plus uncertainty and rethrows; it does not automatically reopen. This is not a VM crash or state-loss test. The client's socket timeout is5seconds and stream duration5..180seconds with a duration+10 total bound, so the old stream may terminate before a30second recovery. Observe old-flow outcome and separately issue fresh probes after recovery; do not promise seamless continuation.

Control and evidence/capture share the same nonblocking lock. Concurrent close/reconcile/capture cannot override a bounded operation; status is read-only and does not prove the lock is free. Let the exact process finish or interrupt that known process with a handled signal, verify process exit/restoration/lock release, then close or reconcile. Never remove the lock file or kill arbitrary processes. SIGKILL, power loss, root interference and I/O failures are outside guaranteed recovery. Durable pending/uncertain/finalizing records and emergency closure are best effort; no multi-file transaction is claimed. Absent markers or a previous success event do not prove a safe current state. Finalizing intent is written before marker removal, followed by stable state; filesystem failures still require actual current policy checks and independent isolation. Reboot preparation closes rather than reopens.

## 9. Rollback, isolation and cleanup

1. Stop/finish the exact bounded client probes and retain their final UTC records. Stop any owned stream using its known process, never indiscriminate kill.
2. After any experiment releases its lock, close E and verify current owned drop policy. If uncertain, investigate and reconcile closed. Do not delete pending/ownership files to bypass checks.
3. Close Firewall Allow and both NSG exposure gates in an authorized reviewed update, retaining deployment/image gates and all routes/management. Verify effective policy and fresh-flow denial. **Do not remove app/Firewall default UDRs first**: system Internet or another path could become eligible.
4. On B stop all three fixture services and verify inactivity plus absence of the listeners. Use a successful query rather than interpreting a failed tool as absence:
```bash
sudo systemctl stop azure-forced-fixture@8080.service azure-forced-fixture@8081.service azure-forced-fixture@8082.service
for port in 8080 8081 8082; do
  state=$(systemctl show "azure-forced-fixture@$port.service" --property=ActiveState --value)
  [[ "$state" == inactive ]] || { printf 'Listener service is not inactive\n' >&2; exit 1; }
done
listeners=$(sudo ss -H -ltn '( sport = :8080 or sport = :8081 or sport = :8082 )')
[[ -z "$listeners" ]] || { printf 'Owned test listener remains\n' >&2; exit 1; }
```
5. Keep private management until evidence and isolation are reviewed. Existing NSG state, packet captures, Firewall session updates and disabled services are separate observations. If stopping a service or isolation verification fails, do not detach routes/policies or destroy while assuming closure.
6. Optional guest-only restoration after verified isolation:
```bash
sudo forced-control close --confirm-guest-change
sudo forced-control restore-original --confirm-guest-change --acknowledge-reviewed-scope
sudo forced-control status
```
This restores only captured owned sysctls, removes the owned table and leaves boot marked restored. It does not reset Azure NIC forwarding, erase conntrack, change NSGs, remove routes or prove remote isolation. Do not use it to fix a corrupted/mismatched ownership record automatically.
7. Review and separately authorize full Terraform teardown of this dedicated lab. `deploy_lab=false` is destructive, not a safety switch. Review dependencies and cost-bearing remnants; do not delete shared image/subscription resources. Verify final RG/resource absence, no PIP/Bastion/disk/log leftovers, and billing implications through approved read-only checks. Retain private state/evidence only under the authorized retention policy.

## 10. Actual VPN/ExpressRoute remains a separate design

A real implementation needs an approved on-premises peer/perimeter, Internet/NAT capability, an IPsec tunnel and selector/crypto/MTU design, secret handling, gateway and supported Default Site or BGP default propagation, precise source-return routes, management separation, monitoring and change/rollback authorization. None of those resources or secrets is hidden behind a flag here. Do not infer that VNet-to-VNet VPN simulates Internet backhaul or that its routes validate an on-premises default. ExpressRoute requires actual circuit/provider/BGP prerequisites and eligible learned routes; FastPath can change the path and must be assessed separately. A VPN `VirtualNetworkGateway` UDR is not a substitute for ExpressRoute routing. Use the full guide's reference architecture only as a separate plan, not as a claim about this executable simulator.
