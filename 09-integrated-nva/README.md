# Scenario 09: vWAN Internet intent with an integrated partner NVA

**Source draft, not self-contained vendor deployment.** This package owns a complete generic Azure test substrate and verification harness. A selected, supported partner security/dual-role NVA, Marketplace/license onboarding, management service, policy installation, SNAT and vendor logs remain **external prerequisites**. An Azure Firewall, arbitrary Linux VM or connectivity-only SD-WAN appliance does not satisfy this scenario. No vendor was selected, purchased, installed or configured here.

All Azure/vendor/actual-guest results are **NOT RUN**. Recovery formatting and a fresh `terraform fmt -check -recursive` passed using an isolated existing formatter; provider initialization, schema validation, plans and supplied mock-plan cases remain NOT RUN. The loopback/fake-CLI checks in [validation/STATUS.md](validation/STATUS.md) describe historical producer work, not fresh recovery coverage. See [recovery qualification](../RECOVERY.md) for the current, narrower offline checks, with [results worksheet](RESULTS.template.md), [source references](SOURCES.md) and the [full guide](../azure-09-vwan-internet-integrated-nva-guide.md).

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. No command is executed by opening this README.

## Owned and external resources

Owned Terraform infrastructure:
- Dedicated RG `inspection-partner`, Standard WAN `lab-wan`, managed Standard hub `partner-hub`, `10.0.0.0/23`.
- App VNet `app`, `10.10.0.0/16`; workload `10.10.1.0/24`; VM/NIC `app`/`app-nic`, **A=10.10.1.10**. No public IP, NAT Gateway, outbound load balancer or implicit default outbound access.
- `connect-app` is the only hub connection, with `internet_security_enabled=true`; no custom `routing` block. There is **no source UDR**, especially no **0/0 -> None** blackhole defeating the learned Internet default.
- Separate **unconnected** origin VNet `origin`, `10.30.0.0/16`; workload `10.30.1.0/24`; VM/NIC `origin`/`origin-nic`, **B=10.30.1.20**. Static Standard IPv4 `origin-public-ip` is attached to B's NIC. Its actual allocated address is **D**, never a documentation address.
- Separate **unconnected** management VNet `management`, `10.40.0.0/16`; `app-bastion` in its AzureBastionSubnet **10.40.2.0/26**. Two ordinary peerings `management-to-app`/`app-to-management` permit VNet access only: gateway transit, remote gateways and forwarded traffic are false. No management hub connection or UDR.
- `origin-bastion` stays local to origin in **10.30.2.0/26**. Both Bastions are Standard with native-client tunneling and mandatory service NSGs. Their HTTPS service public IPs are distinct from D; SSH target access uses private IPs.
- Origin serves bounded, read-only, synthetic plain HTTP on **8080 and8081**, marker `azure-partner-origin-v1`. App has no test listener or reverse mode.

**Why separate management?** Bastion cannot share the app VNet's forced/learned Internet default safely. Its hosting management VNet is not connected to vWAN and does not use a remote gateway. The app's management return uses the more-specific `10.40.0.0/16` peering route rather than the Internet default. This is a documented separate-VNet management pattern, not a Bastion-subnet UDR workaround. Verify actual management reachability and peering settings. Origin remains unpeered and unconnected; this management-only peering is not a private bypass to D/B. See [Bastion routing troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/azure/bastion/troubleshoot-connection-fails-routing-forced-tunneling) and [FAQ](https://learn.microsoft.com/en-us/azure/bastion/bastion-faq).

External ownership: the selected partner installs its managed application and NVA into **this lab's created hub** in a separate stage. Terraform does not create/import/delete publisher-managed children, licenses, management credentials, policy packages or NVA instances. The NVA's actual resource type must be `Microsoft.Network/networkVirtualAppliances`, in the declared same-subscription managed resource group and linked to `partner-hub`. A managed application is required by this chosen ownership contract. A product using a different ownership model needs a reviewed adapter, not a fabricated profile.

## Routing and tuple contract

Once enabled, `internet-inspection` contains exactly `InternetTrafficPolicy`, destination `Internet`, next hop the external **NVA resource ID**, not an IP address. There is no PrivateTraffic policy. Internet-only intent owns Default association and Default propagation. The source connection must learn the default; a hub route table containing0/0 alone does not prove A learned or selected it. Inspect A's actual effective route to D, candidate system default, any unexpected more-specific/split defaults, hub defaultRouteTable and vendor routes. Do not assume a specific displayed NIC route source or internal next hop.

Routing intent programs the Azure platform; the managed hub router is not a separate packet-processing hop in this path. Internet intent is direct egress, not forced tunneling through an on-premises Private policy. Do not add competing connection associations, static routes or route maps. Do not query a Private-policy NVA effective-route view as the canonical Internet-only view; use defaultRouteTable plus supported vendor routing evidence.

Expected ledger, to be **observed**, not assumed:
1. Original initiation is **A:a -> D:8080**. Source NSG and pre-NAT vendor policy see source A.
2. Vendor inspection/direct-egress SNAT produces a final public tuple **E:q -> D:8080**. E is one member of the complete observed egress pool, and q may equal or differ from a. A vendor log may instead expose an intermediate private external tuple S:r; do not label it final E:q without evidence.
3. Azure's separate public-NIC mapping delivers **E:q -> B:8080**. Origin NSG sees public E and private B. Fixture reports E:q, B:8080 and case identity.
4. Public response D:8080 -> E:q reaches vendor session/reverse translation, restoring D:8080 -> A:a and the supported app return route. No unsolicited ingress/DNAT publication on E is needed for that established response.

An E/32 origin allowance identifies a shared public pool, **not A**. Other clients using that pool could reach B if vendor policy allowed them. Verify no competing broad vendor Allow reaches D:8080/8081. No source-preservation-to-origin, X-Forwarded-For, TLS decryption or seamless state-sync claim is made.

## NSGs and safe gates

- `app-nsg` priority100 `test-egress`: outbound A/32 to actual D/32, TCP8080/8081.
- `origin-nsg` priority100 `test-origin-ingress`: inbound complete E/32 list to B/32, TCP8080/8081. Empty-E bootstrap uses a **Deny-only** wildcard source; it cannot become Allow until a valid nonempty pool is supplied.
- Both priority100 rules are Deny until `test_paths_enabled=true`.
- Priority110 SSH: management10.40.2.0/26 to A22; origin-local10.30.2.0/26 to B22. No Internet SSH.
- Priority200 outbound denies AzurePlatformDNS; priority4000 denies other inbound/outbound. Origin's stateful reply to permitted inbound HTTP is distinct from a new outbound initiation. Platform infrastructure exceptions remain; these rules are not a proof of zero Azure infrastructure communication.

All eight booleans default false:
- `deploy_lab`, requiring `image_prerequisites_confirmed` for creation.
- `vendor_ready`, requiring a reviewed complete `vendor_profile` and deployed infrastructure.
- `enable_internet_intent`, requiring the existing compatible external NVA and vendor-ready attestation.
- `fixtures_ready`, `internet_routes_verified`, `vendor_deny_policy_verified`.
- `test_paths_enabled`, requiring all preceding readiness/intent evidence and a nonempty E pool.

`vendor_deny_policy_verified` records the **initial** installed named-Deny baseline, not the currently installed vendor action after later tests. There is deliberately **no Terraform vendor-Allow flag**. Actual Deny→Allow→Deny must be performed and verified through the selected product's supported workflow. Flags are neither permission nor continuous proof. `deploy_lab=false` after creation plans destruction, not a pause.

## Required preparation and sensitive-state handling

Use an approved disposable Azure public-cloud subscription, explicit UUID and available region, appropriate permissions and registered providers, current quotas/capacity and a budget. Verify selected product support for the exact hub `/23`, region, scale, image, software and management versions **before** deployment. Do not resize a partner interface pool or treat a listed vendor family as sufficient compatibility evidence.

Supply an existing approved same-subscription **versioned Compute Gallery image** with Python3, iproute2, SSH, systemd, cloud-init and functioning Azure guest agent. No image build, package installation or public bootstrap egress is included. Confirm its guest policy/proxy/cloud-init are compatible. Use an existing approved SSH public key; never put the private counterpart in files, Terraform or guests. Only local operator SSH uses it.

Terraform >=1.11,<2 and exact AzureRM5.12.0 are declared. Terraform 1.11 is required for the supplied plan-stage mock test overrides; this is not a claim that AzureRM requires that minimum. The genuine provider lock is absent because initialization was not run. Review/create it through separately approved tooling setup. Current official docs were reviewed, but provider schema/API acceptance is not validated. Automatic resource-provider registration is disabled. Existing Azure CLI authentication and approved already-installed `virtual-wan` and `bastion` extensions are needed; helpers disable automatic extension installation and do not log in.

Protect state, plans, tfvars, logs and backups as confidential. Use approved encrypted access-controlled state storage. No state backend is created. The nonsecret profile is still operational metadata, not a place for license strings, passwords, tokens, bootstrap URLs, managed-app parameters or outputs. **Do not intentionally export raw NVA/managed-application JSON:** these schemas can contain plaintext cloud-init/bootstrap data or sensitive parameters/outputs. Azure CLI `--query` filters normal command output **client-side**, after the CLI has received the API response. The collector projects selected identity fields into its normal JSON output; this does not prevent raw secret-bearing fields reaching the CLI process, errors or diagnostic logs. Do not enable `--debug`, `--verbose` or shell tracing. Keep CLI logs and the entire evidence directory private and access-controlled; review and redact an approved copy before sharing. No automatic log redaction or guarantee of secret-free evidence is provided. See [Microsoft's query documentation](https://learn.microsoft.com/cli/azure/use-azure-cli-successfully-query). Vendor exports need the same private review. No vendor provider or credential-generation resource is included, but this is not a blanket assertion that Terraform state is harmless.

## Staged future setup

No Azure operation, vendor installation, apply or destruction is executed by this package creation. The following are future operator steps after separate approval.

1. Edit local inputs, keeping all gates false:

```bash
cp terraform.tfvars.example terraform.tfvars
: "${PUBLIC_KEY_FILE:?Set approved existing PUBLIC key file}"
export TF_VAR_ssh_public_key="$(cat "$PUBLIC_KEY_FILE")"
./scripts/check-local.sh
```

Placeholders intentionally fail validation. After separately approved tool/provider setup, preparatory commands are:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

Init can download provider code and was not performed here. The supplied tests are mock-provider plans, not actual Azure tests. Review a real plan, image, rendered cloud-init, cost and state storage before any authorized deployment. No apply/destroy command is embedded.

2. First authorized infrastructure stage: `deploy_lab=true`, `image_prerequisites_confirmed=true`; all other gates false, `vendor_profile=null`, E empty. This creates owned infrastructure/fixtures with both test NSGs closed and **no routing intent**. Verify management and local origin services. The app has no implicit default outbound mechanism.
3. Select/install/license the compatible vendor managed application into the actual output hub through its supported workflow, outside this Terraform state. Preserve ownership, support references and license terms. If no supported profile/provisioning mechanism is available, stop at **BLOCKED vendor prerequisite**, not a completed end-to-end lab.
4. Complete `profiles/vendor-profile.example.json` with real nonsecret IDs and selected publisher/offer/plan/version, software/manager versions, scale, security/dual-role kind, policy package/rule IDs and evidence references. Supply it as the typed `vendor_profile` object, for example:

```bash
: "${APPROVED_PROFILE_FILE:?Set reviewed nonsecret vendor profile JSON}"
export TF_VAR_vendor_profile="$(cat "$APPROVED_PROFILE_FILE")"
```

**Profile text is operator-reviewed, not automatically redacted.** Never enter credentials, license keys, signed/bootstrap URLs, tokens, personal or other sensitive data in any profile field, including free-text evidence references. The collector copies the declared Terraform outputs, including the whole profile, to private `terraform-outputs.json` without redaction. Review the profile and outputs before collection, and privately review evidence before any approved sharing.

Profile validation enforces this exact owned hub, same subscription, integrated-NVA type, managed-app type and managed-RG relationship. It does not prove license, compatibility, health, policy install or live identity. Record a complete global public E pool in `egress_public_ips`, at most16 unique bare IPv4 addresses, excluding private/shared/documentation/multicast/reserved ranges. E must not equal D. Confirm the pool reflects every active instance/egress choice; don't guess one address.
5. Capture projected identities and compare actual linked hub/vendor/SKU/scale and managed-app publisher/offer/plan/managed RG. Then install explicit exact A/32,D/32,TCP8080 **Deny** and8081 **Deny**, with stable named policy/rules and logging, no competing broad Allow. Review vendor direct-egress, SNAT, original-to-public mapping and reverse route to A. Set `vendor_ready=true` only after actual evidence.
6. Separately authorize `enable_internet_intent=true`, retaining NSG Deny. Wait for actual connection/intent convergence; verify Internet-only Default/Default, source learned default, no bypass/stronger routes, vendor paths and independent management. Refresh/review plan for service-owned computed routing drift; never force old associations back blindly.

## Management, local readiness and runtime public configuration

Use existing approved credentials through Bastion. Before Azure reads or these management commands, `load_context` checks the explicit subscription UUID, six core network IDs (WAN, hub, connection, default route table, origin public IP and management VNet), both exact VM IDs and the exact app/origin NIC ID map against their expected resource group/type/name. It also checks supplied intent and external-profile ID relationships. This is an output identity guard, not proof of authorization, resource existence or guest reachability:

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

For origin, use origin-bastion/origin_vm_id. App Bastion is in the isolated peered management VNet, not the default-learning app VNet. Verify ordinary host keys and target access permissions; no disabling host verification or credential copying.

On each VM:

```bash
umask 077
READY_RUN=$(mktemp -d "$HOME/partner-ready.XXXXXX")
partner-ready > "$READY_RUN/readiness.json"
sudo cloud-init status --long > "$READY_RUN/cloud-init.txt"
ss -ltn > "$READY_RUN/listeners.txt"
```

Origin checks exactly `azure-partner-fixture@8080.service` and `@8081.service`, fixed B IP and source-bound local fixture identity. App checks local configuration/tools/NIC only, with no public test traffic. Initial E=[] is permitted for **local** readiness with `pool_not_ready=true`; it cannot authorize a probe. Cloud-init always keeps E=[] so later E changes do not replace VMs.

Create runtime JSON locally from actual declared outputs:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
umask 077
CONFIG_RUN=$(mktemp -d ./runtime-config.XXXXXX)
./scripts/make-runtime-config.sh app "$CONFIG_RUN/app.json"
./scripts/make-runtime-config.sh origin "$CONFIG_RUN/origin.json"
```

This local-only helper writes new0600 files, performs no upload, and requires valid D plus complete nonempty E. Inspect the exact six public fields: role/private_ip/app_ip/origin_ip/origin_public_ip/egress_public_ips. Securely copy only the corresponding public JSON to its intended VM using your already approved Bastion-native tunnel/file-transfer path; preserve host-key verification. It contains no vendor policy or secrets. Do not replace `/etc` or cloud-init. On the intended guest point the helper at the reviewed private local copy:

```bash
: "${PUBLIC_RUNTIME_CONFIG:?Set reviewed public JSON path on this intended VM}"
export PARTNER_LAB_CONFIG="$PUBLIC_RUNTIME_CONFIG"
partner-ready
```

A changed D or E pool invalidates prior route/NSG/vendor-policy evidence. Close tests and repeat review before new traffic; do not silently widen rules. An E-only update uses the runtime config plus reviewed NSG input change, not VM replacement.

## Evidence and demonstrations

Collector, on the operator computer:

```bash
export SUBSCRIPTION_ID='REPLACE_WITH_APPROVED_SUBSCRIPTION_UUID'
./scripts/collect-control-plane.sh
```

Optional OUT must not exist. Per-command `.json/.stderr/.exit`, start/completion UTC and shell exit preserve partial failures; exit3 means read/comparison failures. Successful reads or identity `MATCH` are **not** route/vendor-policy proof. Missing profile yields an explicit blocked note. Terraform may omit null optional outputs entirely; absent/null NVA and intent IDs are both treated as disabled, with no empty-ID resource requests. Required owned IDs remain strict. The collector saves both NIC routes/NSGs/subnets, app connection, management peerings/subnet and all hub connections, defaultRouteTable routes, intended intent and selected NVA/managed-app fields in normal JSON output. `PRIVATE-HANDLING-REQUIRED.txt` records the client-side filtering and unredacted-output warnings. The collector does not intentionally export complete NVA/managed-app JSON, but CLI reception and diagnostic retention of sensitive fields remain possible. No invented partner KQL schema is supplied.

Required external evidence: supported vendor profile/license/health; exact installed policy revision and named rule action; original A:a→D:p tuple; any intermediate S:r; final public E:q where exposed; session owner; direct/reverse routing and complete E inventory. Origin fixture records final E:q. Export a bounded UTC window using the actual product schema. Missing vendor logs block attributed-Allow/Deny conclusions. Never use Azure Firewall AZFWNetworkRule logs for partner traffic.

After local fixture/route/installed-Deny evidence, set `fixtures_ready=true`, `internet_routes_verified=true`, `vendor_deny_policy_verified=true` and explicitly authorize `test_paths_enabled=true`. Confirm both NSG envelopes are Allow before attributing a timeout to N. Then on A:

```bash
partner-probe closed
```

Require a fresh attempted original tuple, healthy origin8080, correct routes/envelopes and a matching **vendor named8080 Deny**. No TCP connection means the HTTP case ID was never delivered; correlate denied SYNs by tuple/time.

Using the selected vendor's supported install workflow, change **only** named8080 to Allow and record actual installed revision, leaving8081 Deny and all Azure routing unchanged. Then on A:

```bash
partner-probe positive
partner-probe alternate
```

Positive requires identity-matched response at private B8080, final observed peer E:q from the approved pool, original client tuple and vendor Allow/mapping evidence. It does not establish source preservation or final vendor NAT ownership by itself. Alternate8081 requires independently healthy local8081 and named vendor Deny. Absence of origin logs or a timeout alone is inconclusive.

Optional bounded existing-session observation while primary Allow is effective:

```bash
partner-probe stream --duration 180
```

Observe valid frames first, then use the supported vendor closure procedure and record installed revision/time/session behavior. No reconnect or retry occurs; socket timeout is5seconds and total cap is duration+10seconds. **Do not import Azure Firewall's Allow-to-Deny existing-session behavior into this vendor.** If the control change misses the finite stream window, mark inconclusive. Run a fresh closed attempt after closure separately. Instance failure, default withdrawal and state-sync experiments are **not implemented**; they need vendor-supported boundaries/recovery and distinct authorization.

`partner-probe closed|positive|alternate|stream [--out NEW_DIR] [--duration5..180]` saves reviewed runtime-config, pre-SYN connection evidence, connected/request-write stages when reached, frames and final result with completed UTC. Existing paths, even empty directories/symlinks, are refused. Always **NEEDS_REVIEW**; exit0 records a bounded attempt, not network PASS. Preserve incomplete stages after interruption. Copy fixture journal for actual UTC/case with fresh output paths; a completed client write is not receipt proof.

## Closure, ownership-aware removal and costs

1. Stop finite clients; close vendor primary rule through supported workflow and verify actual installed action/new-flow result. Determine existing-session handling from that product and evidence.
2. Stop exactly origin8080/8081 units through independent management; verify each is inactive and `ss` successfully shows no remaining listener. Preserve journals and evidence.
3. Set `test_paths_enabled=false` while infrastructure and intent remain; verify effective source/origin Deny and real isolation. NSGs are stateful: rule edits alone do not prove earlier sessions ended. If anything is uncertain, stop teardown.
4. Only after isolation, separately review removal of the routing-policy reference by setting `enable_internet_intent=false` with infrastructure still deployed. Intent removal changes propagation and does not restore an earlier routing design. Do not call it an automatic safe default-withdrawal test.
5. Use the vendor's own managed-application/orchestrator uninstall path, approved license/management cleanup and publisher restrictions. Do not directly delete protected managed children, bypass deny assignments or assume Terraform owns the external NVA. Verify the hub no longer has an external dependency.
6. Review/authorize teardown of the owned generic resources. Verify residual WAN/hub/connection, three VNets/management peerings, two Bastions/three owned public IPs, two VMs/disks and external vendor resources/billing. The RG safeguard refuses unexpected leftovers; don't disable it automatically. Existing approved image, SSH keys and unrelated management/license assets remain untouched.

Budget actual vendor license/manager/managed application and NVA infrastructure/scale/public IP costs, Standard vWAN hub/connection costs, two Standard Bastions, two VMs/disks, three owned public IPs, peering/Internet data transfer and any vendor log storage. Stopping VMs or closing test rules does not stop those other charges. Use actual region/offer/licensing in the [Azure calculator](https://azure.microsoft.com/pricing/calculator/) and vendor quote. No monetary estimate or successful deployment is asserted. There is no self-contained end-to-end success until a supported vendor profile and complete real evidence exist.
