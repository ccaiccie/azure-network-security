# Scenario 04: Premium TLS inspection, controlled origin

**Local draft, not an Azure-tested deployment.** No resource was deployed, no CA/key/PFX was generated or retrieved, and no repository was changed. Terraform is unavailable in the authoring environment: provider initialization, HCL parsing, `fmt`, `validate`, mock Terraform plans and real plans are **NOT RUN**. Local checks are documented separately in `validation/STATUS.md`. This is an on-demand lab with an included controlled origin, not a zero-prerequisite PKI demo.

[Scenario overview](../README.md) · [Illustrated guide](../azure-04-premium-tls-inspection-guide.md) · [Validation status](validation/STATUS.md)

## What is included, and what remains external

Included: a dedicated resource group, hub and one app spoke, Premium Firewall and policy, two peerings, workload UDR/NSG, DNS proxy, one private Ubuntu client, Standard Bastion and its dedicated public IP/NSG, a B1 Linux App Service with Azure's public default-hostname TLS certificate, original dependency-free Node fixture, diagnostic settings and Log Analytics. There is no database spoke, VM public IP, DNAT, NAT Gateway, broad firewall network-443 rule, forced tunnel, explicit proxy or OS trust-store edit.

The origin infrastructure is Terraform-managed. Publishing the supplied original code is a **separate explicit operator action**, using `scripts/deploy-origin.sh` and Entra-authenticated Azure CLI. No Terraform provisioner, deployment credential or `zip_deploy_file` is used. The ZIP is built locally; it contains only `server.js` and `package.json`. Python run-from-package is not supported by App Service, so the fixture deliberately uses supported Node 24 LTS. No npm install/build/dependencies are needed. The Node patch release is platform-managed, not reproducibly pinned.

Unavoidable external prerequisites are:

1. An existing approved **intermediate inspection CA**, held by an approved Key Vault certificate's versioned secret URI, and the existing user-assigned identity authorized to retrieve it. The lab creates no CA, vault, identity, secret or access grant. It never reads the secret's value. Linking an identity to a policy is a security-sensitive action requiring the organization's specific approval, even if access already exists.
2. Approved **public inspection root CA PEM** for the client and a separate approved **normal public origin trust bundle**, excluding the inspection root, for direct-origin/untrusted tests. Public certificates are not private keys. Their origin and fingerprints must be verified out of band with the PKI owner. Neither bundle is shipped here.
3. An existing SSH key; only the public part enters Terraform. A real approved subscription, operator public IPv4/32, unique app name and concrete available VM image version must be supplied.
4. The approved region's actual resource capacity/quota and ability to retrieve the existing Key Vault secret. These are not established by syntax checks or by the readiness flags.

Do not put CA private keys, PFX bytes, certificate passwords, access tokens or publishing credentials into variables, files, cloud-init, outputs, plans or state. The URI is an identifier, not the secret. Terraform records identity/secret identifiers, public keys and infrastructure metadata, and the AzureRM Linux Web App resource can also export `site_credential` name/password into state. Disabling basic publishing authentication does not make state credential-free. Treat full state and saved plans as secret-bearing, use approved encrypted access-controlled storage, never commit or attach them, and do not print provider credential attributes. The selected outputs and collector deliberately omit those fields. `.gitignore` is an accident guard, not a security boundary.

## Exact topology and policy contract

- Resource group default `inspection-tls`; a new dedicated group, never import shared atlas resources.
- `hub`: `10.0.0.0/16`; `AzureFirewallSubnet`: `10.0.1.0/26`.
- `lab-firewall`: Premium; **F** is output `firewall_private_ip`; **P** is output `firewall_public_ip`. Read actual values, do not assume allocation.
- `app`: `10.10.0.0/16`; `workload`: `10.10.1.0/24`; VM `app`, NIC `app-nic`, **A = 10.10.1.10**.
- `app-inspect`: workload route `0.0.0.0/0 → VirtualAppliance F`, BGP propagation disabled. Workload subnet has default outbound access disabled.
- App VNet DNS is F; policy DNS proxy uses Azure's default resolver upstream. The source VM's system resolver must actually receive/use that configuration.
- `tls-bastion`: Standard, dedicated `AzureBastionSubnet 10.0.2.0/26`, separate public IP, native tunneling enabled. No workload UDR on this subnet. Its mandatory service NSG rules are distinct from workload egress rules.
- `lab-policy`: Premium, threat intelligence **Alert**, IDPS **Deny**. Group `test-rules` priority **200** exists only when inspection and origin-readiness gates are true.
- Application collection `deny-test-url` priority **100**, action Deny, rule `deny-blocked-path`: source A/32, HTTPS443, exact URL `H/blocked`, `terminate_tls=true`.
- Application collection `allow-test-origin` priority **200**, action Allow, rule `allow-approved-origin`: source A/32, HTTPS443, exact FQDN H, `terminate_tls=true`.
- H is the actual `origin_hostname` output from App Service, not a guessed `name.azurewebsites.net`. No scheme or query goes into `destination_urls`. Requests are exactly `https://H/allowed` or `https://H/blocked`, no query, redirect, alternate case or trailing slash. The denial is deliberately narrow; it is not a general path-normalization/WAF policy.

The fixture returns **HTTP200 for both paths** and includes `fixture=azure-tls-origin-v1`, exact path and the `X-Lab-Case-ID` header value. Probe requests also carry `User-Agent: azure-tls-lab/<case-id>` for frontend HTTP-log correlation. `/health` also returns200. Other paths/queries return404, non-GET405. Only synthetic observations are logged. The FW allow is FQDN-wide except the preceding exact deny, so `/health` is also reachable; this is not an allow-only-one-URL policy.

### Workload NSG and origin restrictions

`app-nsg` permits Bastion/26 → A/32 TCP22 inbound at100; A/32 → F/32 UDP53 at100 and TCP53 at101 outbound; A/32 → Internet TCP443 at110. The Internet destination is broad at the **NSG** layer because App Service frontend IPs can change; the firewall's exact-H application rules are the egress boundary. Platform DNS is explicitly denied via `AzurePlatformDNS` at200, followed by deny-other inbound/outbound at4000. External UDP443/QUIC, arbitrary TCP22 and direct external DNS are not permitted. Those bypass classes have source configuration guards, but no implemented live probes in this lab; do not report their runtime enforcement as tested.

App Service's main endpoint allows P/32 (`allow-lab-firewall`,100) and the explicitly approved operator/32 (`allow-approved-preflight`,110), then denies all other sources. SCM deployment permits only that operator/32 (`allow-approved-deployer`,100), with an independent deny default. Basic FTP and WebDeploy publishing authentication is disabled; FTP itself is disabled. The main site still has a public endpoint with Azure-managed TLS and a real cost, even though source-restricted. Never put sensitive content in this fixture.

### Two TLS sessions and three trust boundaries

A addresses H's resolved public destination IP on443. Its UDR steers the connection to F; it does not send an explicit proxy request to F:443. The firewall terminates the client TLS session and presents a generated H certificate signed through the inspection intermediate. It starts a separate TLS session to the public App Service frontend, using its public certificate and application-rule SNAT through P. The two source ports and possibly DNS answers can differ.

1. **Client → inspection CA:** only an approved public inspection root bundle is supplied process-locally to curl/OpenSSL. Nothing updates `/etc/ssl`, a browser profile or OS trust.
2. **Firewall → origin:** Azure Firewall validates the public origin certificate. The inspection CA is a signing CA, not a way to add arbitrary origin trust. Microsoft's Premium known issues state that a customer-signed intranet web server certificate is not trusted by the firewall; this lab therefore uses App Service's publicly managed default certificate.
3. **App Service frontend → Node:** TLS terminates at the platform frontend; the runtime receives platform HTTP. Node's `socket_peer` is an internal platform peer, **not P**. Its raw `forwarded_for_untrusted` field is not authenticated proof of SNAT. Use frontend HTTP/access logs and the applied P/32 restriction, alongside firewall/config evidence, for the egress-source claim. The lab does not capture an origin-side packet tuple or TLS session inside Azure's managed frontend.

## Safety gates and lifecycle

Defaults are `deploy_lab=false`, `enable_tls_inspection=false`, `tls_prerequisites_confirmed=false`, `origin_fixture_ready=false`.

- `deploy_lab=false` gives root module count0. Required inputs are still validated. **Changing it from true to false in an existing deployment plans deletion, not suspension.** Do not use it as a casual pause switch.
- `deploy_lab=true` with other gates false creates chargeable infrastructure, no TLS certificate linkage and no application allow. Workload Internet access remains firewall-default-denied.
- `enable_tls_inspection=true` requires deployment, attestation, versioned URI and same-subscription identity ID. Attestation is not actual retrieval proof and does not replace approval.
- `origin_fixture_ready=true` requires inspection true and creates both application collections. Only set it after the separately published origin passes direct certificate and both-path checks.

Suggested order: authorize/review infrastructure → provision closed infrastructure → publish/verify origin → approve and link preexisting PKI/identity → verify actual CA retrieval/provisioning → enable application rules → copy approved public trust only → run tests. The helpers never apply Terraform or grant access. This README deliberately does not execute or provide a one-command deployment. Any future apply/change/destroy remains a separate reviewed operator action.

## Prerequisites and pre-deployment review

- Terraform >=1.9,<2, AzureRM **5.12.0** exact pin, authenticated approved subscription. `resource_provider_registrations="none"`: required Microsoft.Network, Compute, Storage, Web, OperationalInsights, Insights and existing ManagedIdentity/KeyVault services must already be available/registered as appropriate. No automatic provider registration is performed.
- Azure CLI >=2.75.0; already approved/installed `azure-firewall` and `bastion` extensions. Disable dynamic installation before the runbook. The firewall extension CLI commands otherwise auto-install software. Do not install or sign in without the relevant authorization.
- Python3, Node24 for local fixture tests, zipfile from Python stdlib, Bash, curl built with OpenSSL and OpenSSL3, `timeout`, `getent`, `ip`, `realpath`. The Ubuntu guest must contain these tools and SSH. No package installation or unrestricted bootstrap egress is configured. If the chosen pinned image lacks a tool, prepare an approved image separately, do not add broad temporary Internet rules.
- Existing SSH credential and the permissions required to use Bastion, inspect NIC routes/NSGs, read logs and publish original code. CLI deployment uses Entra authentication with basic publishing disabled. A principal lacking required deployment permission will fail; do not enable basic publishing as a workaround.
- Public operator/32 must be the actual approved NAT source used for both HTTPS preflight and SCM. VPNs/proxies can change it. No automatic public-IP discovery/transmission is performed.
- A maintenance/test window, approved PKI/identity linkage and budget. Existing CA/vault permissions are not inferred from repository permission.

**Region caveat, checked 2026-11-04:** [Microsoft's current known-issues capacity table](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues) lists an **East US Standard** new-deployment block. This lab uses **Premium**, so that row alone does not establish a Premium block or Premium availability. `eastus` remains an example unchanged; verify actual Premium, B1 App Service, Bastion and VM capacity/quota/pricing before choosing the approved region.

### Existing PKI preparation checklist, not executable secret handling

Have the authorized PKI/security owner provide the existing versioned **secret URI** (not certificate URI) and approved UAI ARM ID. They must verify current Microsoft intermediate-CA requirements: a valid intermediate signing CA, exportable RSA private key, PFX with no password, the required CA/basic-constraints and signing key-usage extensions, sufficient chain depth/path length, and valid lifetime. Microsoft specifies a one-year-valid intermediate and an RSA4096 example; do not confuse bytes with key bits. The PFX must contain the required intermediate/key, not a root CA key or an unrelated full chain. Follow the linked current certificate documentation rather than deriving a production CA from this lab.

The existing UAI must already have the required Key Vault secret Get/List access under the vault's chosen access model (for RBAC, an appropriately approved scoped secret-reading role), and the vault's network configuration must permit the firewall's supported retrieval path. Confirm firewall-policy identity linkage, versioned-secret status/expiry, approved vault-network/trusted-service configuration and regional/subscription constraints with the security owner. This module deliberately creates **no** `azurerm_role_assignment`, access policy, private endpoint, trust exception or permission change. A supplied ID can pass syntax validation and still be unusable.

No sample PFX/key command is provided. Do not use `az keyvault secret show/download`, `openssl genrsa/req`, Terraform TLS resources or secret-value data sources in this workflow. For public client trust, use the already-issued approved public root/chain PEM and compare its SHA256 fingerprint to the independently supplied PKI record. The client trust bundle and origin trust bundle are distinct artifacts and purposes.

### Local review, then future authorized plans

```bash
cd lab  # From this scenario package root
./scripts/check-local.sh
cp terraform.tfvars.example terraform.tfvars
# Edit required identifiers and approved nonsecret inputs. Leave gates false.
export TF_VAR_ssh_public_key="$(cat /approved/path/existing-key.pub)"
# After approved Terraform/provider installation, with provider cached or approved download:
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

No lock file was generated because initialization was not run. Generate/review `.terraform.lock.hcl` with verified provider checksums on the approved workstation. The concrete VM image is required; `latest` is rejected. Terraform test mock runs are plan-only but still need the real provider schema/plugin. Mock output cannot prove Azure API support or capacity. Real Terraform plan may contact Azure and read state; run it only in the approved account/context and secure any saved plan. Review every later stage diff, especially replacements and deletion. Changing H/image/custom data may replace the VM; flipping only readiness flags is not embedded in guest custom data.

The example tfvars is intentionally invalid until real approved inputs replace placeholders. Documentation IPs/names and fake test IDs are never deployment values. Resolve image availability explicitly, without silently selecting a version:

```bash
: "${SUBSCRIPTION_ID:?Set the approved subscription UUID}"
: "${LOCATION:?Set the approved region identifier}"
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
az vm image list --subscription "$SUBSCRIPTION_ID" --location "$LOCATION" \
  --publisher Canonical --offer ubuntu-24_04-lts --sku server --all \
  --query '[].version' -o tsv
az webapp list-runtimes --subscription "$SUBSCRIPTION_ID" --os-type linux -o json
az extension show --name azure-firewall -o json
az extension show --name bastion -o json
```

## After separately authorized infrastructure creation

All commands below are **future operator instructions, not actions already run**. From the lab directory, bind commands to actual state and the approved subscription:

```bash
: "${SUBSCRIPTION_ID:?Set the approved subscription UUID}"
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
source scripts/common.sh
load_context # aborts if the firewall state ID is not in the approved subscription
A=$(read_output app_private_ip)
F=$(read_output firewall_private_ip)
P=$(read_output firewall_public_ip)
APP_VM_ID=$(read_output app_vm_id)
BASTION=$(read_output bastion_name)
ADMIN=$(read_output admin_username)
printf 'A=%s F=%s P=%s H=%s\n' "$A" "$F" "$P" "$H"
./scripts/collect-control-plane.sh
```

Inspect provisioning state, the private NIC, effective `0/0→F`, peerings, effective NSGs and app DNS. More-specific connected/peering routes also appear; a VM's `ip route` only shows the guest default gateway and cannot replace Azure effective-route evidence. No tenant-wide inventory is needed.

### Publish and verify the controlled origin

This step uploads only the included synthetic source ZIP to **this lab App Service** and restarts it. It is an external state change requiring deployment/upload authorization, not a read-only preflight. Review the source and ZIP first and record the approved ZIP SHA256 independently. The helper requires that explicit reviewed hash, rebuilds deterministically, snapshots the exact bytes, compares their hash before any upload, and refuses on drift. Do not automatically approve a newly changed hash at upload time. It also requires explicit intent, a state-matched subscription and disabled dynamic extension installation. CLI basic-auth fallback is not used; CLI>=2.48.1 supports Entra deployment when publishing basic authentication is disabled, and this runbook requires the newer overall CLI version above.

```bash
python3 scripts/build-origin.py
# Only after explicit approval to upload the original synthetic fixture to this origin:
: "${REVIEWED_ORIGIN_ZIP_SHA256:?Set the independently reviewed and approved ZIP SHA256}"
./scripts/deploy-origin.sh --confirm-synthetic-origin-upload "$REVIEWED_ORIGIN_ZIP_SHA256"
# Direct public-origin certificate trust, outside the lab inspection path:
./scripts/origin-preflight.sh /approved/public-normal-origin-roots.pem
```

Require both paths to return200, verify normal public TLS/hostname, correct fixture identity/path/case ID, and confirm this host is actually outside the inspection path. A successful default App Service welcome page is insufficient. A403 may mean wrong operator source; a503 may mean startup/deployment failure. Fix the identified issue within approvals, never relax restrictions or use `-k`. Capture frontend source/access logs too. Do not set origin-ready solely because ZIP upload was accepted.

Now the authorized operator may review/set `enable_tls_inspection=true`, `tls_prerequisites_confirmed=true`, the **existing identifier-only** inputs, and later `origin_fixture_ready=true` after actual prerequisite checks. Review separate plans before approved changes. Allow observed provisioning/CA propagation: Microsoft's known issues mention 5–10 minutes for intermediate-CA propagation. Wait for real readiness and fresh results, not a fixed sleep asserted as success. Keep the origin-ready gate false if access/retrieval fails.

## Private management and public trust delivery

Use the already-approved Bastion/native SSH setup. The VM has no public IP; its SSH ingress is only the Bastion subnet. Bastion's own public endpoint is a managed management surface, not a workload firewall bypass. Start a scoped tunnel in a separate terminal; leave it running only during use:

```bash
source scripts/common.sh
load_context
APP_VM_ID=$(read_output app_vm_id)
BASTION=$(read_output bastion_name)
az network bastion tunnel --subscription "$SUBSCRIPTION_ID" -g "$RG" -n "$BASTION" \
  --target-resource-id "$APP_VM_ID" --resource-port 22 --port 50022
```

In another terminal, after verifying the SSH host key through your approved host-verification method, connect and transfer **only approved public PEM certificates**. Do not disable host-key checking. Local port50022 has no direct relationship to test HTTPS443. An existing private SSH key remains local; do not copy it to the VM.

```bash
: "${ADMIN:?Set admin_username from actual output}"
: "${SSH_KEY:?Set path to existing approved SSH private key on this workstation}"
# These two copies require approval for these public certificates and this client.
scp -P 50022 -i "$SSH_KEY" /approved/inspection-root-public.pem "$ADMIN@127.0.0.1:inspection-root-public.pem"
scp -P 50022 -i "$SSH_KEY" /approved/normal-origin-roots-public.pem "$ADMIN@127.0.0.1:normal-origin-roots-public.pem"
ssh -p 50022 -i "$SSH_KEY" "$ADMIN@127.0.0.1"
```

Inside A, inspect cloud-init completion, tool versions, IP and DNS before testing. Cloud-init delivers helper source/config only, not trust material. No package download is needed:

```bash
cloud-init status --wait
ip -4 -o addr show
cat /etc/azure-tls-lab.json
resolvectl status
curl -V
openssl version
python3 /usr/local/lib/azure-tls/public-ca-check.py "$HOME/inspection-root-public.pem"
python3 /usr/local/lib/azure-tls/public-ca-check.py "$HOME/normal-origin-roots-public.pem"
```

Confirm A=10.10.1.10, the actual F is DNS, curl is OpenSSL-backed, OpenSSL3 is present, both bundles contain only approved valid public certificates, and the negative bundle excludes the inspection root **and any alternate trust anchor that could validate it**. The checker detects PEM/key/PFX/expiry/format problems, not your organizational approval or semantic trust exclusion.

## Positive and negative demo

Run only these bounded synthetic requests, sequentially, preserving UTC evidence and fresh connections. No proxy, client config, redirect following, insecure verification or QUIC is used. `curl -q` is its first option, and ambient proxy/CA settings are cleared. Each process uses `--cacert` plus a fresh empty `--capath` on OpenSSL curl; the chain helper additionally disables default CA path/store. `--tlsv1.2 --tls-max 1.2` makes the client profile deterministic without claiming the origin leg uses the same TLS version.

```bash
# Inside A:
tls-probe allowed "$HOME/inspection-root-public.pem"
tls-capture-chain "$HOME/inspection-root-public.pem"
tls-probe blocked "$HOME/inspection-root-public.pem"
tls-probe untrusted "$HOME/normal-origin-roots-public.pem"
```

- **Allowed:** require curl exit0, HTTP200, verify0, exact fixture/path/case ID, a verified H certificate chain rooted in the approved inspection CA, matching application Allow/`allow-approved-origin`/`IsTlsInspected=true`, route viaF and origin receipt. `ORIGIN_IDENTITY=MATCH` is only the fixture check, not a complete inspection verdict.
- **Blocked:** require matching application Deny/`deny-blocked-path`, actual inspected decision where emitted, and no origin receipt for that case after allowing for log delay and corroborating origin logging with positive controls. The client's exact error/status may vary. Both direct-origin paths returned200 beforehand. A timeout,403 or absent log by itself is inconclusive.
- **Untrusted bundle:** expect client certificate-verification failure (typically curl60) under independently approved normal public trust excluding the inspection CA, with valid control results from allowed. No origin request is required because the client handshake may end first. This is a client trust-negative, not proof that Azure Firewall rejected the public origin certificate.
- **Separate chain capture:** `openssl s_client` is a new connection with its own tuple. Verify hostname, cryptographic chain and approved root fingerprint, not just issuer text. Its evidence can support the topology but cannot be labeled the same connection as a preceding curl request.

Optional **implemented pinning contrast**, only if an independent approved origin SPKI pin was already obtained and verified outside the inspection path. The fixture supplies no hardcoded pin and the default Azure origin certificate can rotate. Do not compute a pin from the already intercepted certificate:

```bash
: "${APPROVED_ORIGIN_PIN:?Set independently verified origin sha256// base64 pin}"
tls-probe origin-pin "$HOME/inspection-root-public.pem" \
  "$HOME/tls-evidence/origin-pin-$(date -u +%Y%m%dT%H%M%SZ)" "$APPROVED_ORIGIN_PIN"
```

Expect pin mismatch (typically curl90) even when CA/hostname verification succeeds, because the firewall presents a different leaf key. A stale/wrong pin can also fail directly, so retain its fresh origin-control evidence. If no approved pin exists, record **NOT RUN**, not pass.

The helpers always print `RESULT=NEEDS_REVIEW`; transport exit alone is never a firewall verdict. They retain curl exits, actual local/remote tuple, body/headers, resolver output and diagnostics. Never equate A's observed remote IP with a separately resolved origin connection or claim the App Service runtime socket proves SNAT. No malicious payload/signature test, invalid-origin-certificate fixture, mTLS, generic bypass matrix, QUIC or TLS1.3 client test is implemented. No runtime conclusion on those cases is warranted.

## Evidence and acceptance

After each short test window, collect actual configuration again and query the configured workspace. Use actual IDs/time windows in the supplied `.kql` files. Read-only diagnostic queries still need the approved account and log-reader permission. Do not retrieve Key Vault secret values to troubleshoot.

```bash
source scripts/common.sh
load_context
WORKSPACE=$(read_output workspace_customer_id)
./scripts/collect-control-plane.sh
# Edit copies of query placeholders to actual IDs and UTC bounds first.
az monitor log-analytics query --subscription "$SUBSCRIPTION_ID" --workspace "$WORKSPACE" \
  --analytics-query "$(cat queries/application.kql)" -o json
```

`queries/application.kql` selects source IP/port, FQDN/TargetUrl, protocol, decision, policy/group/collection/rule and `IsTlsInspected`. That table has no `DestinationIp` column; case headers are not present in firewall application logs, so correlate source tuple and UTC window. The unique User-Agent containing the same case ID is available in App Service HTTP logs. `origin-console.kql` finds the exact case in fixture JSON; `origin.kql` supplies frontend HTTP path/status; `origin-access.kql` supplies frontend access/source decisions where emitted. `idps.kql` separates signature/action evidence. IDPS is configured Deny but a benign test with no signature event is **not** an IDPS prevention demonstration. Threat intelligence is Alert, not Deny.

Logs are asynchronous and a table may not yet exist before first ingestion. Empty/missing tables or dropped records are inconclusive. Do not create broad extra logging or relax policy to manufacture a result. Record actual CA/config status, allowed control, negative outcomes and gaps in `RESULTS.template.md`. A full acceptance claim needs correlated routing, DNS, NSG, rules, verified client chain, application decision and origin evidence. It must also name what remains untested.

## Rollback and cleanup

1. Preserve the approved nonsecret evidence and note any secrets accidentally exposed; do not publish logs/state automatically.
2. For a **closed-policy rollback**, review a plan setting `origin_fixture_ready=false` first. This removes application collections and restores default-denied workload egress. Inspect actual effective policy and retest an approved benign request after the separately authorized change. Setting this false does not stop any billable resource.
3. If required, separately review `enable_tls_inspection=false` after origin-ready is false. This unlinks the policy's existing identity/CA reference, but does not delete or revoke the external identity/CA/permissions. Security owner approval may be required. Do not rotate/revoke shared material as lab cleanup.
4. End SSH and the Bastion tunnel with Ctrl-C. The process-local trust configuration is gone when probes exit. Remove only the explicitly approved copied public certificate/evidence files if desired; no OS trust rollback is needed because none was changed.
5. To remove the lab, verify the intended state/workspace/subscription and review a destroy plan against the **dedicated** group. Execute only through the separately authorized operator change process. `deploy_lab=false` on an existing state likewise requests destruction. Confirm every resource is removed and billing stops; a failed delete is not cleanup. Do not delete the preexisting Key Vault, CA, identity or grants.
6. App Service code/package and logs in this dedicated deployment are removed with its resources; retained/exported logs, saved plans/state or external backups have their own retention. Follow the approved handling policy rather than automatically purging evidence.

## Costs and limitations

Premium Firewall has a substantial continuously billed deployment component plus processing; Standard Bastion, B1 App Service plan, VM/disk, public IPs, Log Analytics ingestion/retention and applicable network transfer/peering also cost money. VM stop alone does not stop firewall/Bastion/App Service/disk/IP/log charges. No free-tier claim or live price estimate is made. Use the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) with approved region, hours, traffic and retention; obtain a budget and delete promptly after the test window.

This is a single-region lab without production HA/zone design, operational rotation, centralized policy inheritance, custom origin domains, private App Service endpoint or availability guarantees. Provider/version pinning and local mocks do not validate Azure schema compatibility, quota, CA retrieval, App Service runtime availability, TLS behavior or diagnostic ingestion. Read `SOURCES.md`, the scenario guide and current known issues before a future authorized deployment.
