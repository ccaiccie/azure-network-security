# Scenario 06: two Linux forwarding nodes behind one HA-ports ILB

**Source-complete draft, not a deployed or runtime-validated lab.** This directory supplies an on-demand Terraform topology, Linux forwarding/health fixtures, bounded experiment helpers, evidence collectors and cleanup guidance. It is a synthetic stateful forwarding model, **not a vendor NGFW, supported appliance image or state-synchronized cluster**. All actual Azure behavior and Linux nftables/kernel execution remain **NOT RUN**. See [validation/STATUS.md](validation/STATUS.md), [RESULTS.template.md](RESULTS.template.md), the [full guide](../azure-06-nva-ha-ports-guide.md) and [seven-page atlas](../diagrams/README.md).

No infrastructure, VM, local host firewall, forwarding sysctl, cloud account, repository or secret has been changed to prepare this draft. Local tests use fake control backends/CLI executables and a bounded loopback HTTP server only. Code is not approval to deploy, alter guest security settings, capture traffic or incur charges. Obtain the appropriate approvals for each future activity.

[Scenario overview](../README.md) · [Package integration checks](../validation/PACKAGE-CHECKS.md)

## 1. Concrete topology and safety defaults

- Dedicated resource group `inspection-nva`; explicit approved subscription and region, no region default.
- Hub `10.0.0.0/16`; regular NVA subnet `10.0.2.0/24`, not an AzureFirewallSubnet. `nva1=10.0.2.4`, `nva2=10.0.2.5` each have one NIC, primary static IPv4 and Azure NIC IP forwarding enabled.
- Standard regional internal Load Balancer `nva-ilb`, one frontend `inside=10.0.2.10` (**F**), one `nva-pool`, two NIC backend associations. One `ha-ports` rule: protocol All, frontend/backend port 0, Floating IP enabled, Default five-tuple distribution, outbound SNAT disabled and TCP reset disabled.
- App spoke `10.10.0.0/16`, workload subnet `10.10.1.0/24`, VM `app=10.10.1.10` (**A**). Backend spoke `10.20.0.0/16`, workload subnet `10.20.1.0/24`, VM `backend=10.20.1.20` (**B**).
- App route table `app-inspect`: `10.20.0.0/16 → VirtualAppliance F`. Backend table `backend-inspect`: `10.10.0.0/16 → VirtualAppliance F`. Both also have `0.0.0.0/0 → None`.
- Hub `nva-block-internet` route table has only `0.0.0.0/0 → None`. The NVA forwards through the hub's system peering routes, **not through another route back to F**. No direct spoke peering, gateway transit or alternate LB.
- Standard Bastion `nva-bastion` in `AzureBastionSubnet=10.0.3.0/26` supplies private SSH access. Its public IP is the only public IP. Mandatory Bastion service NSG paths are separate; it has no workload UDR.
- No NAT rule, managed Azure Firewall, DNS dependency, package-download allowance, public workload IP or general Internet egress. Workload/NVA subnets explicitly disable default outbound access. Platform/fabric services are not equivalent to ordinary routed Internet traffic; this is not a blanket proof of blocking every Azure platform channel.

`deploy_lab=false` creates nothing in an **empty** state. Setting it false after deployment plans resource deletion, not a billing pause. Deployment also requires `image_prerequisites_confirmed=true`, an operator attestation, not proof or permission. There is no Terraform switch that silently activates forwarding or advertises readiness.

`nva_zones=null` is unzoned and makes no zone-resilience claim. An optional approved pair such as `["1","2"]` requests distinct NVA VM zones and LB frontend zones 1/2/3. Verify the region, image replication, VM SKU and frontend support first. A/B remain unzoned, so even that setting is not end-to-end zone resilience.

## 2. Unavoidable image and operator prerequisites

The lab consumes one **existing, approved, concrete Azure Compute Gallery image version ARM ID in the same subscription**. It does not create an image, install packages, accept licenses, enable a repository or open Internet egress to compensate for a missing tool. A plain stock image is not enough unless its contents satisfy this contract.

The versioned x64 Ubuntu-compatible image must contain Python 3, curl, `ip`/iproute2, nftables with JSON support, conntrack tools, tcpdump, GNU timeout/coreutils, Bash, systemd, cloud-init and SSH. It must support the strict conntrack sysctl and contain no competing router/NAT/security-agent behavior that defeats the owned nft table. Verify its provenance, support, patching, network/filter defaults and absence of credentials or real user data. Do not build or bake secrets into an image. Choosing a versioned ID avoids `latest` drift; the actual image contents remain an external prerequisite.

Other requirements:

1. A disposable nonproduction subscription/resource group, appropriate quotas and budget, nonoverlapping addresses, existing approved SSH **public** key, and permissions to create the listed network/compute/Bastion resources. Keep the private key in the operator's existing approved secure location. No key generation or transmission is included.
2. Terraform 1.9 or later below 2.0, AzureRM exactly 5.12.0, Python 3 and Bash on the operator computer. Provider authentication is operator-managed and never placed in `.tfvars`. Provider registration is disabled; required resource providers must already be registered through an approved process.
3. Azure CLI and, for native Bastion tunneling, its already-approved installed Bastion extension. Dynamic extension installation is disabled in examples/helpers. Do not let a supposedly read-only collection silently install software.
4. Region/SKU capacity, price, image replication and supported load-balancer probe schema verified at execution time. Azure Firewall's unrelated regional Standard-firewall capacity notices are not a Standard Load Balancer deployment guarantee or restriction.
5. Permissions to read effective routes/NSGs and LB metrics. Optional Network Watcher next-hop queries can require an existing enabled Network Watcher; do not silently create one or install a VM extension.
6. Explicit approval before guest forwarding/security-policy changes and packet capture. Existing SSH access alone is not approval for those actions.

Terraform state and plan files are confidential operational artifacts and may contain provider-returned data or credentials. Although this lab does not intentionally create passwords/keys and has no Log Analytics workspace, **do not label state public or credential-free**. Use an approved encrypted access-controlled state backend for real use; none is configured here. Do not commit state, evidence, tfvars, plans, pcaps or keys. A genuine reviewed `.terraform.lock.hcl` should be retained after approved initialization; none could be generated in this environment.

## 3. Local preparation and static checks

Review every file and the source limitations before any deployment. Only this command is a local check entry point; it does not install software, initialize providers, run Terraform apply, call Azure, or execute nft/sysctl/conntrack/tcpdump:

```bash
cd lab  # From this scenario package root
bash scripts/check-local.sh
```

Prepare a separate working copy and fill the intentionally invalid placeholders in `terraform.tfvars.example`. Supply only an existing public key via the normal input mechanism. Required values remain required even with the deployment gate false.

```bash
umask 077
cp terraform.tfvars.example terraform.tfvars
# Edit approved subscription, location, image version ID and ownership values.
# Set TF_VAR_ssh_public_key to the contents of an approved PUBLIC key, not a key path.
# Leave deploy_lab=false until the proposed deployment is explicitly approved.
```

Future initialization/provider downloads are a separate operator action. After approved initialization, the supplied `tests/baseline.tftest.hcl` contains **10 plan-only mocked-provider cases**. The tests do not create Azure resources; they still require Terraform and the provider schema. Future commands are:

```bash
terraform fmt -check -recursive
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

Review the real subscription-scoped plan and all resulting resource names/costs before any separately authorized deployment. No deployment or destroy command is supplied as an automatic step. The implementation uses no provisioner or local-exec deployment shortcut. Terraform fmt, HCL parsing, provider initialization/validation and mock plan execution were not possible here.

## 4. NSG, guest policy and health are different gates

NIC NSGs are `app-nsg`, `backend-nsg`, `nva1-nsg`, `nva2-nsg`; NICs are the corresponding `*-nic`.

- App outbound priority 100 and backend inbound priority 100 allow A/32 to B/32 TCP 8080 and 8081. Keeping 8081 reachable through Azure NSGs lets the guest's named deny be tested.
- Each NVA has inbound/outbound priority 100 for that original A→B tuple. Inbound/outbound priority 101 permits the reverse-shaped B→A tuple with **source** ports 8080/8081. Destinations are original workload IPs, not NVA IPs. This reverse NSG shape does not authorize arbitrary new reverse sessions in the stateful guest policy.
- Each VM inbound priority 110 permits Bastion subnet SSH to its own IP. NVA inbound priority 120 permits `AzureLoadBalancer` TCP 8008 to its own IP. Outbound 200 denies `AzurePlatformDNS`; all remaining inbound/outbound traffic is denied at 4000. Established NSG return traffic is stateful.

The owned `inet azure_nva_lab` nft table initially drops forwarded traffic. `nva-control activate` installs the closed table first, records original owned sysctl values, sets IPv4 forwarding, then explicitly sets and verifies `rp_filter=2` (loose mode, not disabled), redirect/source-route values 0 and `nf_conntrack_tcp_loose=0`. Changing `ip_forward` can reset other IPv4 parameters, so it is always sequenced first. Restoration covers the captured owned values, **not a full rollback of every OS networking parameter**.

The open model admits only A→B TCP 8080 NEW SYN packets, that direction's established packets and established B:8080→A replies. A→B TCP 8081 has named `deny-alternate-8081`; remaining forwarded traffic drops. It has no SNAT/DNAT, payload inspection or conntrack replication. Strict midstream pickup plus SYN-only NEW admission makes the model more stateful than a generic permissive Linux router. It does not prove actual Azure migration behavior or guarantee any particular old-flow outcome.

Each actual table update first runs `nft -c` on the entire atomic batch, then loads only the owned table. Those operations have **not been run here**, and source tests do not establish real nft syntax acceptance. Other image-installed firewall tables may further restrict forwarding; review the complete baseline rather than flushing them.

Activation leaves health **withdrawn**. `advertise` is separate and requires local checks to pass. The root monitor checks owned policy digest, forwarding/security sysctls and absence of NAT expressions in the nft ruleset every 2 seconds. An unprivileged server on own-IP:8008 `/healthz` returns 200 only for a ready snapshot no older than 6 seconds; otherwise 503. The guest input rule allows Azure's `168.63.129.16` probe source and local loopback for this health port, denying other health sources.

This checks neither B reachability nor Azure NIC forwarding, effective routes, actual LB eligibility, legacy non-nft filtering, CPU saturation or end-to-end availability. The LB probe is HTTP 8008 `/healthz`, interval 5, probe threshold 2 and number-of-probes 2, with explicit `AllProbedDown`. These fields are not a promised 10-second convergence SLA. Observe actual eligibility and allow for detection, metrics delay and flow handling.

## 5. Private access and readiness after an authorized deployment

On the operator computer, first verify local Terraform output and explicitly scope every Azure command to the intended subscription. Never rely on ambient `az account` selection.

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
source scripts/common.sh
load_context
az extension list -o table  # Local installed-extension inventory; no installation.
az account show --subscription "$SUBSCRIPTION_ID" --query '{subscription:id,tenant:tenantId}' -o json
terraform output -json
```

Use a separate foreground tunnel and SSH terminal per VM, changing only the selected VM ID and local port. The example uses the `app_vm_id` output; `backend_vm_id` and the `nva_vm_ids` map provide the others. Verify SSH host keys using the approved deployment channel; never disable host-key checking.

```bash
APP_ID=$(terraform output -raw app_vm_id)
BASTION=$(terraform output -raw bastion_name)
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name "$BASTION" --target-resource-id "$APP_ID" \
  --resource-port 22 --port 50022
```

```bash
# Separate local terminal, existing approved private key stays local.
ssh -p 50022 labadmin@127.0.0.1
```

On B, run `backend-ready`. It verifies both systemd fixture units and **local** HTTP listeners on B:8080 and B:8081. Both return only fixed synthetic identity JSON (`azure-nva-origin-v1`), never files or real data. `/stream?seconds=5..180` on 8080 emits bounded one-second NDJSON frames and a final `stream_end=true` frame. This local readiness proof is essential before diagnosing a dropped remote 8081 request. Check cloud-init/systemd logs if it fails; do not improvise broad egress or package installation.

On each NVA, `sudo nva-control status` and `systemctl status nva-boot nva-health-monitor nva-health` are read-only. Initially forwarding is closed and health is withdrawn. Missing tools, wrong private IP, unsupported kernel settings, conflicting policy or syntax errors are blockers, not reasons to advertise.

Run the scoped control-plane collector after deployment and at meaningful transitions:

```bash
# Operator computer; final directory must NOT already exist.
RUN=$(mktemp -d "$HOME/nva-control-run.XXXXXX")
bash scripts/collect-control-plane.sh "$RUN/baseline"
```

It saves the LB/frontend/pool/rule/probe, all four NIC IP-forwarding flags, effective routes/NSGs, subnet associations, route tables, peerings and DipAvailability/VipAvailability metrics. It uses only read APIs after prerequisites. Any API failure retains timing and partial evidence; it is not a complete snapshot.

## 6. Bounded demo and evidence plan

All commands below are **future operator actions**, not test results. Security mutations must be approved for the specific node/action. `--confirm-guest-change` is an acknowledgement required by the helper, not a replacement for authorization. Run only on the indicated VM. Never direct probes to F: the client destination remains **B:8080/8081**.

### Establish a known owner before testing failover

1. Verify B's two listeners with `backend-ready` and save its service journal.
2. On each NVA, inspect status and any pending recovery. Activate each explicitly; they remain withdrawn.
3. Advertise only nva1 first. Wait for observed nva1 eligible/nva2 ineligible state, not a guessed sleep duration. New flows should select the only eligible node, but retain packet/conntrack evidence before labeling ownership.
4. Capture both nodes, then run fresh positive and negative requests from A. Repeat with only nva2 eligible as a separate single-node control before combined HA tests.

```bash
# Each NVA, separately authorized. Activation leaves it withdrawn.
sudo nva-control activate --confirm-guest-change
sudo nva-control status
# nva1 only for the first single-owner control:
sudo nva-control advertise --confirm-guest-change
```

```bash
# A. Reserve a new grouping directory; do NOT precreate the child outputs.
RUN=$(mktemp -d "$HOME/nva-cases.XXXXXX")
nva-probe positive --out "$RUN/positive"
nva-probe negative --out "$RUN/negative"
```

```bash
# On BOTH NVAs in separate sessions, start before the A probes.
# Root output may need approved owner/access handling before export.
sudo nva-evidence --capture-seconds 30
```

`nva-probe` accepts `positive|negative|stream`, optional `--duration 5..180` and `--out NEW_DIR`. It refuses any existing final output directory, file or symlink. The default creates a unique case directory under the invoking user's `~/nva-evidence`. Each TCP attempt binds A to an ephemeral port and writes `connection.json` **before connect**, preserving `attempted_local`, `attempted_destination`, case ID and `started_utc`. On connection success it adds actual local/remote tuple and `connected_utc`. `result.json` always retains completion UTC, elapsed time, connect status, request-write status and errors; `frames.ndjson` preserves received frames incrementally.

Short probes have a 5-second socket timeout and 15-second total bound. A stream has the same 5-second socket timeout and a duration+10-second total bound, so a 30-second outage may terminate it long before recovery. It never reconnects or retries. A successful HTTP response is checked for exact fixture/case/peer/server identity; stream completeness also requires sequential frames, the final marker and duration. Exit 0 can mean a completed **negative/error observation**, not PASS: inspect the evidence. Preflight errors exit nonzero. The HTTP case header and User-Agent are sent only after TCP connects; an 8081 SYN DROP is correlated by attempted tuple and UTC, **not by a nonexistent backend HTTP case record**.

Expected decision rows, all presently NOT RUN:

| Case | What must be established, not assumed |
|---|---|
| Single-owner fresh 8080 | Fixture identity MATCH, B sees A, both tuple directions on one eligible NVA, matching established conntrack and route/NSG evidence. |
| Fresh 8081 | B listener locally healthy, NSGs permit this test, attempted tuple retained, selected NVA's named 8081 counter/capture proves drop, no successful backend HTTP. Timeout alone is inconclusive. |
| Both nodes advertised | Several distinct fresh source-port flows can distribute; prove each flow's two directions use one owner. No equal-distribution claim from a small sample. |
| Health-only withdrawal | Existing stream and new-flow selection are separate observations. It does not stop forwarding or erase state. |
| Bounded forwarding failure | Owned forward policy closes for 5..120 seconds while health withdraws. New eligibility and old-flow completion/error must be measured separately. Conntrack is retained. |
| Both nodes withdrawn | After observed convergence, fresh flow should have no eligible backend with AllProbedDown. Existing flows can differ; this is not proof all traffic instantly stops. |
| Restoration | Exact recorded health/mode restored, fresh 8080 succeeds and controlled 8081 still drops; preserve separate before/after evidence. |

For a long-lived test, establish a proven single owner first, start A's stream, retain its initial tuple and both-node evidence, then advertise the survivor and verify its eligibility **before** interrupting the old owner. Coordinate separate terminals; do not serially wait for the stream to finish before starting the failure.

```bash
# A, foreground in its own terminal; begin only after a known owner is established.
RUN=$(mktemp -d "$HOME/nva-stream.XXXXXX")
nva-probe stream --duration 120 --out "$RUN/original-stream"
```

```bash
# Proven owning NVA, one approved experiment at a time.
sudo nva-control withdraw-for --seconds 30 --confirm-guest-change
# Different run, after reestablishing a proven owner and ready survivor:
sudo nva-control fail-forwarding --seconds 30 --confirm-guest-change
```

During each interval, start separate new `positive` cases on A with new directories. Keep the original stream's tuple distinct from replacement connections. Health withdrawal preserves the open data plane; `fail-forwarding` installs a closed owned forward chain. Neither stops a VM, changes routes/NICs, toggles `ip_forward` during the interval or flushes conntrack. This is **not a crash, reboot, state-loss or vendor HA failover test**. Strict pickup rejects midstream adoption in this synthetic model, but observed transport/selection behavior still needs actual runtime evidence.

Both bounded actions hold an exclusive control lock, save a recovery record and restore recorded policy/advertisement in `finally`. SIGHUP, SIGINT and SIGTERM are handled; SSH output failure does not prevent event persistence. Every attempt writes private `/var/lib/azure-nva-lab/experiments/<action>-<time_ns>/events.jsonl`, recording start/restoration or restoration failure UTC, node and duration. The exclusive lock remains held throughout the interval and restoration, then is released when the controlling file descriptor closes or its process exits. Concurrent mutating commands, including `close`, `withdraw` and `recover`, fail immediately while it is held; read-only `status` remains available but does not acquire the lock or prove it is free. Finish the bounded run or use an approved handled interruption of that known foreground process, inspect restoration events/status, and confirm the process has ended and the lock is released before issuing another control action. Do not delete the lock file to bypass mutual exclusion. SIGKILL, VM loss, reboot or restoration error can require explicitly authorized recovery. Do not infer recovery just because the shell ended.

`nva-evidence` accepts `--capture-seconds 0..120` and optional `--out NEW_DIR`, also refusing any existing final path. It saves before/after local health/status, guest routes, nft JSON/counters, scoped conntrack output plus its error/exit, and optionally bounded `transit.pcap` limited to the synthetic A/B TCP 8080/8081 tuples. It writes start/end/shell exit. `ip route get` inside a VM is guest routing evidence, **not the Azure effective next-hop table**. An empty conntrack snapshot can miss a short-lived flow; it does not prove another node owned it. Capture both nodes and preserve ingress/egress direction, tuple and sequence numbers.

LB `DipAvailability` with BackendIPAddress is supporting aggregate probe evidence; `VipAvailability` is a separate frontend datapath metric. They are not per-flow owner logs. VipAvailability can take up to 10 minutes to appear after creation/update, and standard byte/packet/SYN bandwidth metrics do not capture UDR-directed internal-LB traffic. No Azure Firewall tables, vendor session logs or fabricated LB flow logs are used.

## 7. Recovery, rollback and cleanup

Read status and persistent events before choosing an action. If a recovery record remains, `activate`, `advertise` and `restore-original` refuse to overwrite that baseline. `close`/`withdraw` are permitted with a leftover recovery record only after the earlier controlling process has ended and released the exclusive lock; they cannot override a still-running experiment. If it is still running, let it finish or use an approved handled interruption, verify restoration and lock release, then close or withdraw. These actions do not erase the record. `recover` explicitly restores the previously recorded mode and advertisement, potentially reopening forwarding; approve that exact consequence first.

```bash
# Relevant NVA only, after inspecting status/events and approving restoration.
sudo nva-control status
sudo nva-control recover --confirm-guest-change
sudo nva-control status
```

For normal test rollback, restore intended advertisement flags, verify both nodes' health and fresh positive/negative controls, and retain before/after evidence. To stop forwarding safely, use `close` on both NVAs. It closes the owned policy and withdraws health while preserving current sysctl settings. `restore-original` additionally restores captured owned preactivation sysctl values and removes only the lab's owned persistent sysctl file; it leaves a closed table. It is not global firewall cleanup or a full OS-reset mechanism.

```bash
# Separately authorized stop, each NVA, only after any bounded process has
# finished/interrupted, restoration was inspected and its lock was released:
sudo nva-control close --confirm-guest-change
sudo nva-control status
# Optional explicit owned-sysctl rollback only, no pending recovery record:
sudo nva-control restore-original --confirm-guest-change
```

Persistent activation survives reboot through `nva-boot`, which installs a closed table first before attempting the recorded approved open state. Any stale recovery record still requires inspection; do not rely on reboot as a complete rollback. No helper deletes conntrack state or flushes unrelated firewall rules.

Stopping probes, withdrawing health or closing a guest table does **not** stop billing. After evidence review and explicit deletion approval, inspect a destroy plan for this dedicated resource group/state, confirm no unrelated/shared resources were added, then perform cleanup using the approved operator workflow. Never remove the external gallery image or operator key as lab cleanup. Verify deletion and residual charges. Protect retained evidence under an approved retention period, then use the organization's normal authorized disposal process.

## 8. Costs and limits

Ongoing charges can include four VMs, managed disks, Standard Load Balancer rules/data processing, Standard Bastion, its public IPv4, peering/data transfer, image storage/replication and optional monitoring/export. Bastion and allocated resources can cost money while no traffic runs. Prices depend on region, SKU, currency and current terms; use the official [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) and service pricing before approval. No cost estimate or price is invented here.

Not implemented or validated: vendor NVA certification/licensing, state/config replication, real machine crash, seamless established-session failover, production security/IPS/TLS inspection, scaling/throughput/fairness, IPv6, UDP/ICMP demos, fragmentation, cross-region HA, Gateway Load Balancer, multiple frontends/pools, public ingress, DNS or Internet egress. Modern HA ports documentation includes ICMP capability, but this lab's policy/test envelope deliberately does not. UDR-directed HA-port TCP idle timeout is not a failover timer. Two nodes and an ILB alone never prove HA or symmetric state ownership.
