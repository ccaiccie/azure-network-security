# Scenario05: a network rule can hide an application restriction

**Executable local draft, not an Azure-tested deployment.** No resources, DNS records, policies or repository files were changed. No real Terraform plan/apply or live Azure traffic test was run. Terraform/OpenTofu/HCL parser are unavailable; provider initialization, formatting, validation and supplied mock Terraform plans remain **NOT RUN**. See `validation/STATUS.md` for the narrower local tests actually performed.

This derivative is a private **plain HTTP** policy experiment. It intentionally replaces the original public HTTPS smoke test with two controlled hostnames on one private origin. It needs no CA, private certificate, public origin service, secret, package download or trust-store change. Only synthetic case identifiers are sent. HTTP is useful for observing the decision here, not a production confidentiality design.

[Scenario overview](../README.md) · [Illustrated guide](../azure-05-policy-precedence-guide.md) · [Validation status](validation/STATUS.md)

## Complete included resources

- Dedicated resource group `inspection-policy`; do not import shared or production resources.
- Hub VNet `hub 10.0.0.0/16`, `AzureFirewallSubnet 10.0.1.0/26`, Standard `lab-firewall` and standalone `lab-policy`. **F** is the actual `firewall_private_ip` output. Its service public IP **P** exists and costs money, but is neither the destination nor source in this private experiment.
- App VNet/VM `app`, `10.10.0.0/16`, workload subnet `10.10.1.0/24`, NIC `app-nic`, **A=10.10.1.10**.
- Backend VNet/VM `backend`, `10.20.0.0/16`, workload `10.20.1.0/24`, NIC `backend-nic`, **B=10.20.1.10**. Neither VM has a public IP.
- Four explicit hub/spoke peering objects, VNet access/forwarded traffic enabled, no app/backend direct peering, gateway transit or BGP.
- `app-inspect`: remote `10.20.0.0/16→F` and default `0/0→F`; `backend-inspect`: remote `10.10.0.0/16→F` and default `0/0→F`. Both use `VirtualAppliance`, and BGP route propagation is disabled.
- Private DNS zone `policy.test`, manual A records `allowed.policy.test` and `denied.policy.test`, both B, TTL30. Only the hub is linked (`hub-resolution`), autoregistration disabled. A/B VNet DNS points to F; firewall DNS proxy uses Azure DNS and the hub-linked private zone. No baseline hosts overrides or curl `--resolve` are used.
- Standard `policy-bastion`, dedicated `AzureBastionSubnet 10.0.2.0/26`, separate public IP, native tunnel support and required service NSG. No workload route table on Bastion, no customer NSG/UDR on AzureFirewallSubnet.
- Two backend-owned systemd fixtures, bound to **B only**, TCP8080 and TCP8081. Both hostname variants are healthy at the origin. Python standard library only, fixed JSON, no directory/file serving, bounded paths/headers/socket wait/concurrent handlers.
- Subnet NSGs, disabled workload default outbound access, Log Analytics `policy-logs` (30days) and Dedicated firewall diagnostics for Network, Application, DNS and ThreatIntel.

No NAT rule, Internet workload allow, inherited parent policy, IDPS, TLS inspection, NAT Gateway, service/private endpoint, external role grant or key generation is present. The only test network Allow is the explicit opt-in exact8080 override. Bastion's managed public endpoint and mandatory outbound service rules are separate management traffic, not workload egress permission.

## Policy interface and safe defaults

Inputs:

- `deploy_lab=false`: root module count0 in empty state. **Changing true→false on an existing state plans destruction, not suspension.** Required nonsecret inputs are still validated.
- `fixtures_ready=false`: operator attestation only, set after actual backend-local controls succeed. Terraform cannot prove a healthy listener through this flag.
- `policy_mode="closed"`: exactly `closed`, `application`, `network-allow` or `network-deny`. Nonclosed requires deploy_lab and fixtures_ready true.
- `experiments_confirmed=false`: either network override mode requires true, following review and authorization for that specific dedicated-lab change. A flag is not permission by itself.

All user test groups are absent in **closed**, even if fixtures_ready=true. DNS proxy and private management remain configured. Do not infer every possible packet is silent: the service/control plane and the firewall's built-in infrastructure handling are separate. Test the bounded A→B tuple.

In every ready nonclosed mode, `app-controls` priority200 contains:

| Collection | Priority/action | Rule | Source / match |
|---|---|---|---|
| deny-test-host |100 Deny|deny-denied-host|A/32, Http8080, denied.policy.test |
| allow-test-host |200 Allow|allow-approved-host|A/32, Http8080, allowed.policy.test |

Also present is `negative-controls` priority300, network collection `deny-alternate-port` priority100/Deny, rule `deny-app-alternate-port`: **A/32→B/32 TCP8081**. This named control is an explicit addition to the design brief's default-deny suggestion; it does not match8080.

Only a network override mode adds `network-override` priority**65000**, containing exactly one network collection at**65000**:

| Mode | Collection/action | Rule | Scope |
|---|---|---|---|
| network-allow |allow-exact-backend / Allow|allow-app-backend|A/32→B/32 TCP8080 |
| network-deny |deny-exact-backend / Deny|deny-app-backend|A/32→B/32 TCP8080 |

The application Allow and Deny remain configured during both overrides. The enum prevents simultaneous conflicting experimental Allow/Deny collections. Restoration selects **application** again; `application-restored` is a test label, not an accepted enum value. Changes to these mode/readiness flags are not embedded in VM cloud-init, avoiding an intended VM replacement for each mode change. Always inspect the real plan for unexpected replacements.

### What the ordering demonstration means

Azure evaluates rule types before comparing group/collection priorities across those types. The exact network8080 rule can decide before the application group despite its much larger numeric priority. Within a type, hierarchy and group/collection order matter; the matching rule terminates that path. User application rules are followed by built-in infrastructure rules and default deny. Threat intelligence is configured **Alert**, not a prevention claim. This Standard lab has no active IDPS or TLS-inspection stage. [Rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)

Do not add overlapping network Allows for traffic whose application restriction must remain authoritative. A network rule can be narrow at L3/L4 and still defeat the intended Host restriction for its exact flow. Terraform block order and a diagram's box positions do not determine policy evaluation. These are logical checks inside a firewall, not additional routers.

## Different source identities and return routes

Let **a** be A's observed client port, **I** the firewall-managed private application proxy source in `10.0.1.0/26`, and **q** its observed backend-facing port. Never assume I=F or q=a. Network private-range options cannot disable application proxy SNAT. [SNAT behavior](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range)

| Successful flow | Client-side tuple | Backend-side tuple | B's reply next hop |
|---|---|---|---|
| application/allowed |A:a→B:8080|I:q→B:8080|I falls under hub10.0/16 system peering, ahead of0/0UDR |
| network-allow/either host |A:a→B:8080|A:a→B:8080|A matches remote10.10/16UDR→F |

For A→B, the explicit remote10.20/16UDR selects F over the broader RFC1918 system10/8 None and defaults. At F, the backend10.20/16 peering route reaches B. For return traffic, the remote10.10/16UDR or the hub10.0/16 peering wins as above; F then reaches A through app peering. DNS to F also takes the more-specific hub peering path. These are expected route deductions, not captured tables. Collect actual effective NIC routes and associations. Guest `ip route` alone cannot show Azure fabric UDR decisions. [Azure routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview)

The backend logs its actual transport peer and port. HTTP XFF may contain A for a proxied request, but the `xff_untrusted` field is not authentication and never replaces socket-peer evidence. A network-forwarded client can supply arbitrary XFF. This private backend is unlike App Service: its Python socket peer directly distinguishes A from I without a managed frontend in between. P is not the private proxy source.

A rule Allow does not prove routing, NSG permission, healthy listener or delivery. An application Deny may return an HTTP error page, so receiving bytes/HTTP403 or curl exit0 does not mean the origin answered. Replies use existing state; a new B→A connection would be a separate flow and is not implemented as a reverse-new experiment here.

## Exact workload NSGs

All rules below use specific VM destinations/sources and TCP except DNS as stated. No NSG changes are needed between modes.

- `app-nsg` outbound100 `allow-backend-tests`: A/32→B/32 TCP8080,8081.
- `backend-nsg` inbound100 `allow-direct-app-tests`: A/32→B/32 TCP8080,8081.
- Backend inbound101 `allow-proxy-tests`: AzureFirewallSubnet10.0.1/26→B/32 TCP8080,8081. Both source classes are intentional and necessary for the two modes.
- Both inbound110: Bastion10.0.2/26→ownVM/32 TCP22.
- Both outbound200/201: ownVM/32→F/32 UDP53/TCP53.
- Both outbound210: explicit Deny to `AzurePlatformDNS`; both directions4000: deny other new flows.
- Backend has no allowed new application/service egress. NSG state permits replies to admitted inbound requests, provided routing works.

TCP8081 is deliberately allowed by the workload NSG envelope and has a healthy fixture so the named firewall Deny is the intended negative. If actual effective NSGs differ, stop and classify the result as inconclusive instead of blaming the firewall.

## Prerequisites, region and cost review

Required explicit inputs: approved Azure public-cloud subscription UUID, **approved available location with no default**, concrete Canonical Ubuntu24.04 server image version, and existing public SSH key. `latest` is rejected. Existing private SSH key stays on the approved workstation. Resource-group and admin-user inputs have validation; names/quotas still need Azure verification.

**Checked2026-11-04:** Microsoft's [current capacity table](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues#current-capacity-constraints) blocks new **Standard** Firewall deployments in **East US** and lists additional regional/zonal constraints. This lab is Standard. Do not copy an old eastus default or assume a sample mock-test region has capacity. Check Firewall, Bastion, VM quota/image availability, Azure Policy and pricing before selecting the approved region.

Approved workstation prerequisites:

- Terraform>=1.9,<2 with AzureRM exact5.12.0; no provider lockfile was generated here. Initialize only from approved sources and review checksums before retaining the lockfile.
- Azure CLI>=2.75, already approved/installed azure-firewall and bastion extensions. Dynamic extension installation is disabled by all helpers. Do not install software or sign in implicitly.
- Bash, Python3, curl, SSH/SCP, existing credentials and authorized rights to the dedicated subscription/resources/logs.
- Required providers already registered, including Microsoft.Network, Compute, Storage, OperationalInsights and Insights as appropriate. Automatic provider registration is disabled. Registration/permissions are not supplied as lab side effects.

Pinned guest image must already contain Python3, curl, Bash, iproute2 (`ip`,`ss`), getent, systemd, cloud-init and SSH. No apt/npm/download or broad bootstrap egress is configured. Prepare an approved image separately if tools are absent. The fixture has no third-party dependencies or keys. Custom data is public source and nonsecret topology, but **Terraform state and saved plans must be treated as secret-bearing**. AzureRM5.12 Log Analytics workspace exports `primary_shared_key` and `secondary_shared_key`; disabling local authentication does not establish that provider-returned shared keys are absent from state. Use approved encrypted, access-controlled storage; never commit, attach or print full state/plans or those fields. Selected outputs/collector do not expose the keys. Never paste credentials into variables or evidence. [Pinned workspace schema](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/log_analytics_workspace.html.markdown)

Continuously billed components include Standard Firewall, Standard Bastion, two VMs/disks, two public IPs, DNS zone/queries, logs/retention and applicable transfer/peering. Closed policy and stopped VMs do not stop all charges. Use the [Azure calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for the chosen region/hours/traffic; no live quote or free-tier claim is made. Obtain a budget and a short removal window before deployment.

## Local checks and future operator preparation

Commands in this runbook are future operator instructions, not actions already performed. No command applies Terraform. Keep a separate root/state, and do not attach the lab policy to a shared firewall.

```bash
cd lab  # From this scenario package root
./scripts/check-local.sh
cp terraform.tfvars.example terraform.tfvars
# Edit required nonsecret inputs and keep all gates closed initially.
export TF_VAR_ssh_public_key="$(cat /approved/path/existing-key.pub)"
# Only after approved tool/provider installation:
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

The supplied mock tests use plan commands, not apply. They still need the real provider plugin/schema and are NOT RUN here. AzureRM5 DNS A/link resources use `private_dns_zone_id`, not the removed zone/resource-group input combination. Current official provider docs were reviewed, but only actual initialization/validation can establish acceptance by the pinned schema. No static source guard is an HCL parser. A real plan can contact Azure and read state; it requires approved account context and does not constitute deployment authorization.

Resolve the intended pinned image and inspect installed extensions explicitly:

```bash
: "${SUBSCRIPTION_ID:?Set approved subscription UUID}"
: "${LOCATION:?Set approved available region}"
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
az vm image list --subscription "$SUBSCRIPTION_ID" --location "$LOCATION" \
  --publisher Canonical --offer ubuntu-24_04-lts --sku server --all \
  --query '[].version' -o tsv
az extension show --name azure-firewall -o json
az extension show --name bastion -o json
```

After reviewing a future infrastructure plan, deployment itself must occur only through the separately authorized operator process, initially with `deploy_lab=true`, `fixtures_ready=false`, `policy_mode="closed"`, `experiments_confirmed=false`. The backend fixture source is original synthetic code carried in VM custom data; its upload/installation is part of that separately approved deployment, not something done while authoring this draft.

## Private management and fixture controls

After authorized creation, bind every resource command to actual state and the approved subscription. The helper aborts on mismatch and uses no ambient subscription:

```bash
: "${SUBSCRIPTION_ID:?Set approved subscription UUID}"
source scripts/common.sh
load_context
A=$(read_output app_private_ip)
B=$(read_output backend_private_ip)
F=$(read_output firewall_private_ip)
BASTION=$(read_output bastion_name)
ADMIN=$(read_output admin_username)
printf 'A=%s B=%s F=%s mode=%s\n' "$A" "$B" "$F" "$(read_output policy_mode)"
./scripts/collect-control-plane.sh
```

Use a scoped Bastion tunnel for each VM. Example backend tunnel in a dedicated terminal:

```bash
source scripts/common.sh
load_context
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" -g "$RG" \
  -n "$(read_output bastion_name)" --target-resource-id "$(read_output backend_vm_id)" \
  --resource-port 22 --port 50022
```

Another terminal may tunnel A using app_vm_id and local50023. Verify SSH host keys through the approved procedure; never disable host-key checking. The local forwarded port is not a workload service port.

```bash
: "${ADMIN:?Set admin_username from actual output}"
: "${SSH_KEY:?Set local existing approved SSH private key path}"
ssh -p 50022 -i "$SSH_KEY" "$ADMIN@127.0.0.1"
```

Inside B, inspect and run local controls:

```bash
cloud-init status --wait
cat /etc/azure-policy-lab.json
sudo systemctl status azure-policy-fixture@8080.service azure-policy-fixture@8081.service --no-pager
ss -lnt
policy-ready
sudo cat /var/log/azure-policy-readiness.log
sudo journalctl -u azure-policy-fixture@8080.service -u azure-policy-fixture@8081.service \
  --since '10 minutes ago' --no-pager -o cat
```

Require both active services bound to10.20.1.10 and four local HTTP200 controls: both Host names on both ports, exact fixture/case identity, peer=B and server=B. `policy-ready` does not test Azure DNS or firewall policy. It uses local B's address plus Host headers only for local fixture health. This is distinct from A's normal-DNS tests. A failed cloud-init or inactive service must be fixed/diagnosed before readiness is asserted; do not open egress or restart unrelated services as a shortcut.

The systemd units use DynamicUser, no new privileges, read-only system protection and a private temp directory. Each server has a5s socket timeout, bounded32 concurrent handlers, capped request/header content and fixed paths `/probe` and `/health`. This remains a disposable fixture, not a hardened production server.

Inside A, verify actual resolver configuration, both name answers and absence of local overrides:

```bash
cloud-init status --wait
cat /etc/azure-policy-lab.json
ip -4 -o addr show
resolvectl status
getent ahostsv4 allowed.policy.test
getent ahostsv4 denied.policy.test
cat /etc/hosts
curl -V
```

Both names must resolve only to B through the intended DNS proxy. The probe also rejects either name in `/etc/hosts`, records lookups and refuses unexpected IP answers. These checks are not an authenticated DNS proof; correlate the actual VNet DNS setting/resolver and zone/link records. DNS cache/propagation can delay initial resolution. Do not replace DNS with hosts entries or curl `--resolve` to label a failed baseline successful.

## Bounded experiment sequence

Each mode transition is a separately reviewed future cloud change, not a helper side effect. Retain the before/after policy exports, routes, effective NSGs, UTC window and readiness controls. Never change route/NSG/fixture behavior between modes to manufacture the expected result. Wait for actual successful policy provisioning, then use fresh connections and unique cases; a Terraform output alone is not proof the effective policy has converged.

### 1. Closed control

With the initial closed mode, no user test groups exist. You may run the bounded probe to record lack of successful origin access, while DNS/management remain available. Require actual deciding evidence for a denial claim, not merely a timeout. No named application rule should be claimed in this mode.

### 2. Application baseline

After all local fixture controls pass, review/set `fixtures_ready=true`, `policy_mode="application"`, leaving experiments_confirmed=false. Through the authorized change process, deploy the planned policy. Inspect actual groups before testing. Inside A:

```bash
policy-probe allowed
policy-probe denied
policy-probe alternate-port
policy-probe allowed
```

Expected, not observed here:

- `allowed`: HTTP200 fixed fixture/case/Host/path; application Allow `allow-approved-host`; B peer **I within10.0.1/26**, not A. Log its actual port/address; do not assume I=F.
- `denied`: application Deny `deny-denied-host`; no successful origin record for that case, bracketed by healthy allowed controls. Client response shape is not fixed and can be an HTTP proxy error.
- `alternate-port`: named network Deny `deny-app-alternate-port` on8081, with recent local8081 readiness and effective NSGs permitting that envelope. This negative is explicitly nonoverlapping with8080.

### 3. Opt-in network Allow bypass

Review the exact one-flow override, set experiments_confirmed=true and policy_mode="network-allow", and perform only the approved change. App Deny stays present at its original priority. Then:

```bash
policy-probe allowed
policy-probe denied
policy-probe alternate-port
```

Both8080 names should now produce correct fixture responses. The deciding rule must be **network Allow `allow-app-backend` in network-override/allow-exact-backend**, despite application Deny still configured. B's peer should switch to **A=10.10.1.10**, with the original network connection ports.8081 remains the named negative. Do not infer precedence merely from absent application logs; logs can be delayed or miscorrelated.

### 4. Opt-in network Deny contrast

Review policy_mode="network-deny" with experiments_confirmed=true. It replaces the Allow override, never leaves both. Retain healthy backend controls, then:

```bash
policy-probe allowed
policy-probe denied
```

Both8080 requests should fail to produce a healthy origin response and have network Deny **deny-app-backend** in deny-exact-backend. The configured application Allow cannot override that earlier-type match. A failure without a matching decision and health/routing controls is inconclusive.

### 5. Restore and prove baseline behavior

Review policy_mode="application", experiments_confirmed=false, fixtures_ready=true. Verify the network override group is absent, while application and negative groups remain. Repeat allowed/denied/alternate/allowed and backend controls. Require allowed=healthy proxy sourceI again, denied=named application Deny,8081=named negative. This observed source and decision transition, not merely a successful update, completes restoration evidence.

The helper interface is `policy-probe allowed|denied|alternate-port [OUT]`. Omit OUT for a new timestamp/PID case directory, as in the examples. If supplying OUT, it must be a **new nonexistent path** for this one case: the helper atomically creates it and refuses every existing path, including an empty directory or symlink. Do not precreate OUT or reuse a mode directory across calls. This prevents overwriting earlier evidence and prevents stale bodies from a previous run appearing in a later failed request. It checks it is on A, requires both DNS answersB, uses IPv4 HTTP/1.1 and normal URLs (`http://HOST:PORT/probe`), no redirect/proxy/config, `curl -q` first,5s connect/15s total timeout, a unique case header and matching `User-Agent: azure-policy-lab/<case-id>`. It verifies fixed JSON identity and reports `DIRECT_APP_SOURCE`, `FIREWALL_SUBNET_PROXY_SOURCE` or `UNEXPECTED_SOURCE` when a valid fixture body is present. Each newly created case directory gets `timing.txt` with `started_utc`, then `completed_utc` and `shell_exit` on normal shell exit, including a handled preflight failure. The case file also records request-time UTC. An abruptly killed process may lack completion; retain that as incomplete rather than inventing an end time. A curl failure is separately recorded in `exit.txt`; shell_exit0 is not a firewall pass. It always ends `RESULT=NEEDS_REVIEW` after the request path. That observation is not a substitute for the current mode, logs and routes. No sensitive inputs are accepted or sent.

## Evidence collection and exact acceptance

Collect before/after configuration from the operator workstation:

```bash
./scripts/collect-control-plane.sh
source scripts/common.sh
load_context
WORKSPACE=$(read_output workspace_customer_id)
# Edit query copies with actual firewall ID and exact UTC bounds first.
az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
  --analytics-query "$(cat queries/network.kql)" -o json
az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
  --analytics-query "$(cat queries/application.kql)" -o json
```

The collector has the same fresh-output rule: an explicit OUT must not already exist, including empty directories. Its default includes UTC and PID; it records start/completion/shell status in `timing.txt`. If grouping captures, create a parent directory but pass a new child path, not the precreated parent. The collector reads actual policy/groups, diagnostics, both NIC routes/NSGs, subnet associations/route tables, peerings, VNet DNS and private-zone records/link. It does not query inaccessible managed firewall NICs, deploy Network Watcher or mutate resources. If using an already authorized Network Watcher next-hop tool, query A→B, B→A and B→the **observed** I, never a guessed I; that is supplemental route evidence, not a policy verdict.

Network rows contain destination IP/port and exact action/rule. Application rows contain FQDN/TargetUrl and source tuple, not DestinationIp. This is HTTP, so `IsTlsInspected=true` is not an acceptance criterion. Neither table carries the HTTP case header. Correlate each fresh client source port and UTC window with backend `case_id`, host, peer and local port in the journal. Preserve query rows and local artifacts privately; don't attach state or sensitive logs without authorization.

On B, locate the exact case safely:

```bash
: "${CASE_ID:?Set the exact recorded synthetic case ID}"
sudo journalctl -u azure-policy-fixture@8080.service -u azure-policy-fixture@8081.service \
  --since '15 minutes ago' --no-pager -o cat | grep -F -- "$CASE_ID"
```

No-match is expected for many denied requests, and grep then exits1. Run this query independently or inside an `if` when using errexit; it is not a state-changing cleanup command. Absence alone is never proof. Establish logging with nearby positive cases and allow for log delivery/retention. System journal persistence across reboot is not configured; collect evidence during the test. Firewall Log Analytics delivery is asynchronous and a table may be absent before first events. Missing data stays **INCONCLUSIVE/NOT RUN**, not a pass.

Use `RESULTS.template.md` to record controls, actual I, current mode, precise deciding rule and gaps. No parent inheritance, DNAT, TLS/IDPS, reverse-new flow, broad DNS/QUIC bypass or Internet egress experiment is implemented. Those remain conceptual cross-references, not hidden coverage of this Standard HTTP lab. Microsoft documents differing caveats around inheritance/DNS; any future extension must explicitly configure child DNS and verify supported behavior, not extrapolate from this standalone lab.

## Rollback and cleanup

1. Preserve nonsecret evidence and exact owned resources. For restoration, remove the override by returning to application and run the full fresh baseline controls as above. Do not add broad allows or change NSGs to make a failing result disappear.
2. For a closed-policy rollback, review/set policy_mode="closed", experiments_confirmed=false; fixtures_ready may also be reset false. All user test groups are removed. Verify actual policy and a bounded A→B negative; DNS and Bastion stay available. This **does not stop billing**.
3. End SSH sessions and scoped Bastion tunnels with Ctrl-C. There is no CA, trust-store, private-key distribution or external fixture rollback.
4. Review a destroy plan only against the dedicated group/state/subscription, then execute removal only through the separately approved operator process. deploy_lab=false in existing state also requests destruction. Confirm all Firewall/Bastion/VM/disk/public-IP/DNS/log resources are gone and charges end; a partial/failed delete is not completion.
5. Retain or remove evidence/state according to the approved policy. Do not purge shared zones/policies, other labs or unrelated resources. This module creates new associations; it does not import/replace existing ones or promise restoration of external associations.

This is a single-region disposable teaching lab, not production HA, authenticated HTTP, operational monitoring or a complete policy inheritance test suite. Exact schema acceptance, selected image behavior, region capacity, DNS proxy/private resolution, actual managed proxy source, Host behavior, active-session transitions, routing and diagnostic ingestion remain unvalidated until an authorized Azure run.
