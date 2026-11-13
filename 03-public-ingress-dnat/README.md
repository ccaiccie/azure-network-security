# Azure Firewall public DNAT ingress lab

**Independent draft, 4 November 2026. No Azure resources were created, queried or changed. No Terraform/provider validation, real plan, deployment, public request or Azure traffic test has run.** Local-only checks are recorded in [validation/STATUS.md](validation/STATUS.md).

This is a self-contained one-spoke derivative of scenario03, not an edit to the published native-hub repository. It omits that root's unused app VNet/VM and unrelated network/application allows. It publishes a synthetic **plain HTTP** fixture at `http://P:8443`, translated to backend `10.20.1.10:8080`. It does not implement the older illustration's backend `.20:443` or TLS.

**Internet exposure is off by default:** `publish_dnat=false`. Firewall, Bastion and the VM still cost money if this unpublished configuration is deployed. Enabling publication requires an actual approved external client IPv4/32, a reviewed plan and separate authorization for deployment/exposure. A source IP is not user authentication; a shared NAT can represent many devices. Send no credentials or real data over this unencrypted fixture.

[Scenario overview](../README.md) · [Illustrated guide](../azure-03-public-ingress-dnat-guide.md)

## Contract and packet path

| Component | Actual lab configuration |
|---|---|
| Dedicated resource group | `inspection-dnat` default, configurable |
| Hub | VNet `hub`, `10.0.0.0/16` |
| Firewall | `lab-firewall`, Standard; `AzureFirewallSubnet`, `10.0.1.0/26` |
| Public P | Computed `firewall_public_ip`; never a documentation address |
| Frontend F | Computed `firewall_private_ip`, used as workload /0 next hop |
| Instance I | Observed backend peer within `10.0.1.0/26`; do not assume I=F or stable across connections |
| Backend spoke | VNet `db`, `10.20.0.0/16`; subnet `workload`, `10.20.1.0/24` |
| Backend B | VM `db`, NIC `db-nic`, `10.20.1.10`, TCP8080 only, no public NIC IP |
| Private management | `dnat-bastion`, Standard, subnet `AzureBastionSubnet`, `10.0.2.0/26`, separate public IP |
| Workload security/routing | `db-nsg`, `db-inspect`, both associated to backend subnet |
| Policy | `lab-policy`; group `test-rules` priority200 when published |
| DNAT | `publish-test` priority100, action `Dnat`, rule `operator-only` |
| Diagnostics | `dnat-logs`, 30 days, Dedicated/resource-specific logs |

There are exactly two connected hub/db peering objects with VNet access and forwarded traffic enabled, gateway flags disabled. Bastion is **included**, not an optional preexisting resource, but its management path is separate from public test traffic.

For public client C:c, Azure Firewall's documented public DNAT path also applies SNAT:

1. Public request: `C:c → P:8443`.
2. Backend receives: `I:q → 10.20.1.10:8080`.
3. Backend replies: `10.20.1.10:8080 → I:q`.
4. Firewall reverses both translations: `P:8443 → C:c`.

Observe q rather than assuming it equals c. A laptop's local source port can also differ from the public c after upstream NAT. The backend does **not** see C as its socket peer, and no trusted original-client X-Forwarded-For header is supplied by this firewall-only design. The fixture ignores client-supplied XFF. Original C belongs in firewall NAT evidence. [Microsoft's public DNAT/SNAT walkthrough](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gateway/firewall-application-gateway#azure-firewall-only-design)

## Exact policy, NSGs and route selection

Published-demo settings:

```hcl
publish_dnat           = true
allowed_client_cidr    = "YOUR_ACTUAL_APPROVED_PUBLIC_IPV4/32"
enable_default_route   = true
return_route_blackhole = false
```

The CIDR above is deliberately an invalid placeholder. The required input accepts one canonical public IPv4/32 and conservatively rejects private/shared, documentation, reserved and broad ranges. Validation cannot establish ownership or the current NAT/VPN source. Obtain that from an approved network source before exposure. Do not broaden the rule if the client's public address changes; re-review the specific replacement /32.

The only firewall publication is TCP from `allowed_client_cidr` to actual P:8443, translated to B:8080. No separate network Allow is needed for a matching DNAT connection. No network/application collections, inherited policy or custom SNAT settings are configured. A later network Deny cannot narrow an already matched DNAT rule. Threat intelligence is Alert for attributable lab observations, not a production hardening recommendation. [DNAT policy tutorial](https://learn.microsoft.com/en-us/azure/firewall/tutorial-firewall-dnat-policy), [Rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)

Backend subnet NSG:

| Priority | Direction | Source → destination | Port | Action |
|---:|---|---|---|---|
| 100 | Inbound | `10.0.1.0/26 → 10.20.1.10/32` | TCP8080 | Allow translated requests |
| 110 | Inbound | `10.0.2.0/26 → 10.20.1.10/32` | TCP22 | Allow Bastion private management |
| 200 | Outbound | Any → AzurePlatformDNS | Any | Deny direct platform DNS |
| 4000 | Inbound | Any → Any | Any | Deny other new traffic |
| 4000 | Outbound | Any → Any | Any | Deny other new traffic |

The service allow is the **whole AzureFirewallSubnet**, not C/32, P/32 or F/32. It covers managed firewall instances; the DNAT rule applies external source restriction before translation. NSG state admits response traffic for the allowed connection. There is no NIC NSG or broad ephemeral-port exception. [NSG processing](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-group-how-it-works), [NSG state](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)

`db-inspect` normally contains one user route: `0.0.0.0/0 → VirtualAppliance F`. It controls separately initiated outbound traffic, which the policy/NSG currently do not allow. For a DNAT reply to observed I, the hub peering `10.0.0.0/16` is more specific than that /0 and is the expected selected route. Query B's effective routes/next hop to **I**, not just C or F. At the hub, the backend peering `10.20.0.0/16` provides onward reachability to B. These are design deductions until actual route evidence is collected. [Route selection](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview)

No customer UDR/NSG is placed on AzureFirewallSubnet, and no workload inspection UDR is attached to Bastion. There is no forced tunneling, management NIC, gateway, Route Server, private endpoint, load balancer, NAT Gateway, Application Gateway, WAF or TLS termination. The backend subnet explicitly disables default outbound access. DNS is unnecessary for literal-IP tests and is not allowed from the backend. Azure platform exceptions mean this is not a promise of zero platform communication.

## Prerequisites, costs and reproducibility

Before a future deployment, approve the actual subscription, dedicated scope, region, services, public exposure, duration, spending and cleanup.

**Dated region blocker, verified 4 November 2026:** Microsoft currently lists new Azure Firewall **Standard deployments in East US as blocked**. This draft retains `eastus` as its original sample/default; it is not a deployment-ready region recommendation. Stop before deployment, recheck the current capacity notice, and explicitly review/approve another region if the block remains. Update `location` in the owning tfvars and the read-only preflight `REGION` together only after that decision. No region was changed here. [Microsoft current capacity constraints](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues#current-capacity-constraints)

- Terraform `>=1.9,<2.0`, pinned AzureRM **5.12.0**, approved Azure CLI/OpenSSH/Bash/Python3/curl on the operator workstation.
- Preapproved installed Azure CLI extensions: `azure-firewall` for firewall policy commands and `bastion` for native management. Log Analytics CLI queries additionally require `log-analytics`; the portal is an alternative. Automatic first-use extension installation must be disabled for these read-only instructions.
- Existing authorized Azure credentials and SSH key pair. Provide only the **public** key to Terraform. No credential, role assignment, identity grant or private key is generated.
- Already registered Microsoft.Resources, Microsoft.Network, Microsoft.Compute, Microsoft.OperationalInsights and Microsoft.Insights providers. Automatic AzureRM provider registration is disabled; missing registration is a separately authorized subscription action.
- Approved region with Firewall Standard, Bastion Standard and one compatible x64 VM allocation. `eastus`/`Standard_B1s` are examples, not verified capacity.
- A concrete approved `Canonical:ubuntu-24_04-lts:server` image version. `latest` is rejected. The image must already contain Python3, curl, Bash, cloud-init, systemd and iproute2 (`ip`, `ss`). No package download is attempted.
- Permissions scoped to the dedicated lab, effective route/NSG reads, Bastion VM access and log queries. No public SSH fallback or broad Run Command allowance is supplied.
- A controlled external client whose actual public IPv4/32 is known. A second controlled external source outside that /32 is needed only for the excluded-source test. Without it, mark that test NOT RUN.
- Azure Policy must permit the two service public IPs, private subnet associations and selected image/tags. Do not disable governance to make the sample deploy. A regional Network Watcher is optional and must already be authorized for next-hop checks.

Read-only checks after authorized sign-in. Set `SUBSCRIPTION_ID` to the approved UUID before preflight; no command changes the account default. After deployment, verify the approved UUID against this lab's firewall resource ID, as shown in the management section; stop if they differ. Every subscription-scoped manual command below passes it explicitly; extension-list/show reads only local CLI installation metadata.

```bash
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
: "${SUBSCRIPTION_ID:?Set the approved subscription UUID before preflight}"
: "${REGION:?Set the reviewed region matching terraform.tfvars}"
az extension list --query '[].{name:name,version:version}' -o table
az account show --query '{subscription:id,tenant:tenantId,name:name}' -o json --subscription "$SUBSCRIPTION_ID"
az provider show --namespace Microsoft.Network --query registrationState -o tsv --subscription "$SUBSCRIPTION_ID"
az provider show --namespace Microsoft.Compute --query registrationState -o tsv --subscription "$SUBSCRIPTION_ID"
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv --subscription "$SUBSCRIPTION_ID"
az provider show --namespace Microsoft.Insights --query registrationState -o tsv --subscription "$SUBSCRIPTION_ID"
az vm list-skus --location "$REGION" --size Standard_B1s --all -o table --subscription "$SUBSCRIPTION_ID"
az vm image list --location "$REGION" --publisher Canonical --offer ubuntu-24_04-lts --sku server --all -o table --subscription "$SUBSCRIPTION_ID"
```

Stop for separate authorized installation if a required CLI extension is missing. The collector also disables dynamic extension installation and checks `azure-firewall` before resource reads.

**This is not free.** Budget for Firewall Standard provisioned time/data, Bastion Standard two scale units, one VM/OS disk, two Standard public IPv4 addresses, peering traffic and log ingestion/retention. Idle Firewall/Bastion remain billable; `publish_dnat=false` and stopping the VM do not stop those charges. No fixed price, spending cap or daily log cap is claimed. Obtain current region/account/currency pricing and an approved duration. [Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/), [Bastion pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/), [Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)

No genuine `.terraform.lock.hcl` is supplied because initialization did not run. Retain/review the lock produced by approved initialization; do not invent hashes. Protect state and plans, which may contain provider-returned workspace keys even with local authentication disabled. Team use needs a separately approved encrypted/locked backend. Concrete image selection avoids silently changing `latest`, but region availability still requires checking.

## Prepare, validate and review before deployment

All commands below are **future authorized operator instructions**, not claimed executions.

```bash
cd lab  # From the scenario package root
cp terraform.tfvars.example terraform.tfvars
# Supply subscription, region, concrete image, approved actual /32 and ownership.
# Keep publish_dnat=false until the intended publication is reviewed.
export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
./scripts/check-local.sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

The local suite uses only loopback 8080 and fake curl/Azure/Terraform commands and fake sudo/systemctl for the cleanup runbook; it does not probe the example public addresses embedded in mocks. If port8080 is occupied, do not kill its owner. Report the conflict.

`init -backend=false` can download provider packages; it is **not inherently offline**. True offline initialization needs a previously approved populated provider mirror. Eleven supplied Terraform test runs use a mocked provider and `command=plan`; never remove the mock and accidentally run them against real Azure. They cover exact NSGs/DNAT/routes, publication gating, last-route removal, blackhole routing and bad input rejection. They have not run here.

Only after prerequisites and scope are settled:

```bash
terraform plan -out=lab.tfplan
terraform show -no-color lab.tfplan
```

Review actual identity/scope, costs, image/provider, public exposure flag/source, two service public IPs, no backend NIC public IP, NSG/route associations, two peerings, no broad outbound Allow and expected resource counts. **Stop for deployment authorization.** An authorized operator can execute the reviewed plan through the approved process. Deployment success alone does not establish readiness or public reachability.

Outputs include actual RG/location, P/F/firewall identity/policy, backend VM/NIC/subnet/route IDs and B, Bastion name/admin username, workspace ARM ID/customer GUID, allowed source, image and experiment flags. `public_http_url` is null while unpublished and otherwise a plain HTTP URL; it is not a successful test result.

## Private management and backend readiness

On a local management workstation, not Cloud Shell:

```bash
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
RG=$(terraform output -raw resource_group_name)
BASTION=$(terraform output -raw bastion_name)
USER_NAME=$(terraform output -raw admin_username)
DB_ID=$(terraform output -raw backend_vm_id)
FW_ID=$(terraform output -raw firewall_id)
SUBSCRIPTION_ID=$(printf '%s' "${SUBSCRIPTION_ID:?Set the approved subscription UUID}" | tr '[:upper:]' '[:lower:]')
STATE_SUBSCRIPTION_ID=$(printf '%s' "$FW_ID" | cut -d/ -f3 | tr '[:upper:]' '[:lower:]')
if [[ "$STATE_SUBSCRIPTION_ID" != "$SUBSCRIPTION_ID" ]]; then
  printf 'Stop: Terraform firewall state belongs to a different subscription.\n' >&2
  exit 1
fi
az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$DB_ID" --subscription "$SUBSCRIPTION_ID" \
  --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
```

Verify host keys with the approved process; never disable host-key checking. Bastion's separate NSG includes its required AzureCloud/internet dependencies. Those are **not backend outbound permissions**. [Bastion NSGs](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg), [Native SSH](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)

Run Command is not the management path. Its result delivery needs outbound TCP443 to Azure public endpoints; missing output can occur after execution. Do not add broad backend egress to make it work. [Run Command dependency](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)

Cloud-init writes the original fixed-response fixture at `/opt/azure-dnat-lab/server.py`, config at `/etc/azure-dnat-lab.env` and `.json`, owned `azure-dnat-fixture.service`, and `/usr/local/bin/dnat-ready`. It enables the service and captures local readiness at `/var/log/azure-dnat-readiness.log`. The service binds B:8080, not 0.0.0.0; it returns bounded fixed JSON, never files, and records UTC/case/peer/server tuples to its journal. It uses DynamicUser and read-only system protections. It is still a synthetic HTTP test service, not a production hardened application.

Inside **B**, before external probes:

```bash
cloud-init status --wait
sudo cat /var/log/azure-dnat-readiness.log
sudo /usr/local/bin/dnat-ready
sudo ss -lntp
sudo systemctl status azure-dnat-fixture.service --no-pager
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.20.1.10:8080/ready-local
```

Readiness verifies the correct local address, owned service activity, HTTP200 and local fixture identity. A local readiness response legitimately has peer B, not I; only the external public request should expose instance I. Missing/inactive listener makes application-failure attribution inconclusive. No 8081 listener exists or is needed for the unpublished8444 test.

## Exact public demo and evidence

### 1. Preserve the actual configuration

From the management workstation:

```bash
./scripts/collect-control-plane.sh
terraform output experiment_settings
P=$(terraform output -raw firewall_public_ip)
F=$(terraform output -raw firewall_private_ip)
ALLOWED=$(terraform output -raw allowed_client_cidr)
```

Publication tests require `publish_dnat=true`, `enable_default_route=true`, `return_route_blackhole=false`, approved through the deployment workflow. Keep actual policy/group/source/mapping, private subnet/no NIC public IP, both Connected peerings, effective NSGs/routes, hub/firewall/Bastion subnet associations and Dedicated diagnostics. A configured rule is not proof of packet delivery.

### 2. Positive from the approved external client

Set C to that client's actual known public source. Do not derive it from the laptop's private `ip addr` or assume VPN/proxy/NAT behavior. The script records your declaration but cannot independently verify it; correlate C with the firewall NAT row.

```bash
# On the approved external client. Copy only this script/config if using another host.
: "${P:?Set actual lab firewall public IPv4}"
: "${ALLOWED:?Set the actual approved public IPv4/32}"
: "${C:?Set the current client actual public IPv4}"
./scripts/client-probe.sh positive "$P" "$ALLOWED" "$C"
```

Each invocation makes one fresh synthetic HTTP request, has a unique case ID and records UTC, declared public source, curl status/local and remote socket tuple, response headers/body and stderr under `./evidence/`. `curl -q` is first to ignore `.curlrc`; the call uses IPv4, HTTP1.1, no proxy/redirect following and bounded timeouts. No TLS is negotiated. Shell exit0 means evidence was collected, **not PASS**.

Positive acceptance requires all of:

- HTTP200 and matching case; JSON `fixture_role=backend`, `server_ip=10.20.1.10`, `server_port=8080`, peer I inside `10.0.1.0/26`.
- NAT row for original C:c → P:8443 under `lab-policy / test-rules / publish-test / operator-only`, translated destination B:8080.
- Backend journal with matching case and I:q; selected backend return route to that observed I through hub peering /16.
- Client response from P:8443, with local/upstream NAT distinctions recorded.

Do not require I=F or I=C, c=q, a reverse Allow log, a WAF verdict or a translated-source field in the NAT table.

### 3. Backend journal and return route to observed I

Inside B:

```bash
sudo journalctl -u azure-dnat-fixture.service --since '10 minutes ago' --utc --no-pager -o cat
```

Record I from the **matching external case**, not `/ready-local`. On the management workstation, with an existing authorized regional Network Watcher:

```bash
: "${I:?Set observed backend peer IP from the external case}"
az network watcher show-next-hop -g "$RG" --vm db --nic db-nic --subscription "$SUBSCRIPTION_ID" \
  --source-ip 10.20.1.10 --dest-ip "$I" -o json
```

Also retain `db-effective-routes.json`. Compare selected hub-peering prefix `10.0.0.0/16` against /0. Tool enum labels can vary; do not fabricate one. If Watcher is unavailable, mark the next-hop call NOT RUN and retain effective-route evidence. Do not create a Watcher or query a hidden managed-firewall NIC incidentally.

### 4. Resource-specific logs

Use `queries/nat.kql`, replacing actual firewall resource ID and P. Portal Logs requires no CLI extension. With an already approved installed `log-analytics` extension:

```bash
FW_ID=$(terraform output -raw firewall_id)
SUBSCRIPTION_ID=$(printf '%s' "${SUBSCRIPTION_ID:?Set the approved subscription UUID}" | tr '[:upper:]' '[:lower:]')
STATE_SUBSCRIPTION_ID=$(printf '%s' "$FW_ID" | cut -d/ -f3 | tr '[:upper:]' '[:lower:]')
if [[ "$STATE_SUBSCRIPTION_ID" != "$SUBSCRIPTION_ID" ]]; then
  printf 'Stop: Terraform firewall state belongs to a different subscription.\n' >&2
  exit 1
fi
WORKSPACE=$(terraform output -raw workspace_customer_id)
mkdir -p evidence
sed -e "s|FIREWALL_RESOURCE_ID|$FW_ID|g" \
    -e "s|ACTUAL_FIREWALL_PUBLIC_IPV4|$P|g" queries/nat.kql > evidence/nat.kql
az monitor log-analytics query --workspace "$WORKSPACE" --subscription "$SUBSCRIPTION_ID" \
  --analytics-query "$(cat evidence/nat.kql)" -o json > evidence/nat-rows.json
```

`AZFWNatRule` records matching DNAT rules and original source/destination plus translated **destination**. It has no Action or TranslatedSourceIp column. Obtain I:q from B. **Unmatched packets produce no NAT row**, not a NAT Deny row. `queries/unmatched.kql` checks network/threat-intelligence tables as supplemental evidence, without promising every unmatched packet appears. Initial ingestion can take up to 30 minutes; absence alone is inconclusive. [NAT schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnatrule), [Monitoring and match-only NAT logs](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall#resource-specific-mode)

### 5. Negative tests and positive controls

From the same approved C, test an unpublished public port:

```bash
./scripts/client-probe.sh unpublished-port "$P" "$ALLOWED" "$C"
./scripts/client-probe.sh positive "$P" "$ALLOWED" "$C"
```

8444 has no DNAT mapping. Require unchanged policy showing only 8443, a healthy 8080 listener, no successful fixture response on 8444 and healthy 8443 controls before/after. Do not call a timeout or absent NAT row sole proof of rejection. A backend 8081 listener is irrelevant.

From a **second controlled external network outside the allowed /32**, after establishing its actual public source C2:

```bash
: "${C2:?Set the second controlled client actual public IPv4}"
./scripts/client-probe.sh excluded-source "$P" "$ALLOWED" "$C2"
```

The helper rejects C2 inside ALLOWED. Declaration still needs independent network/source evidence; a differently named laptop behind the same NAT is not an excluded source. Require unchanged narrow mapping, source evidence, no valid backend response/case, healthy authorized positives before/after and available network/flow diagnostics. No NAT Deny row is expected. If source cannot be verified or no second approved network exists, leave **NOT RUN/INCONCLUSIVE**, not PASSED.

### 6. Optional bounded endpoint captures

Not automated. Use only already installed approved capture tools around one synthetic request. On B:

```bash
sudo timeout 25 tcpdump -ni any -s 96 \
  'tcp port 8080 and net 10.0.1.0/26' -w /tmp/dnat-backend-headers.pcap
```

A separate client capture can filter `tcp port 8443 and host ACTUAL_P`. Capture only authorized test traffic; even 96-byte snapshots may contain some payload. Public and backend source ports need not match. No managed Firewall packet capture, storage account, public blob or SAS token is supplied or authorized by this lab.

### 7. Record and retain evidence

Use [RESULTS.template.md](RESULTS.template.md), with actual observed results distinct from expectations. Retain configuration, readiness, cases, server records, NAT rows and route evidence together. Redact public source/subscription/tenant/private-topology details before publication; never publish state, plans, keys or unrelated logs.

For authorized backend evidence transfer, use a separate local Bastion tunnel:

```bash
az network bastion tunnel -g "$RG" -n "$BASTION" --target-resource-id "$DB_ID" --subscription "$SUBSCRIPTION_ID" \
  --resource-port 22 --port 50022
# Another local terminal, with approved host-key verification:
# First export only the needed journal/readiness evidence to the user's own folder.
scp -P 50022 -i "$HOME/.ssh/your-approved-key" -r \
  "$USER_NAME@127.0.0.1:/home/$USER_NAME/dnat-evidence" ./evidence/backend
```

Create/export that folder explicitly in B's session before copying; it is not generated by the readiness helper. `az network bastion ssh` is not a file-transfer command. Do not broaden permissions on unrelated files.

## Optional controlled experiments, exact rollback and withdrawal

These changes are **separately authorized, disruptive experiments**, not tests already performed. Preserve owning configuration, state, actual policy/source/P/F, routes/NSGs and off-VM evidence first. Use fresh connections after changes. The three Terraform flags do not enter cloud-init, so toggling them is not intended to replace the backend; review the actual plan for unexpected changes.

### Listener unavailable, then restore

Only after explicit approval to interrupt this owned fixture, run the following block in **B's Bastion session**. Keep a second terminal ready on C for the external probe. The subshell confines shell options and traps to this experiment; the expected inactive status is tested inside `if`, so an outer `set -e` cannot skip restoration.

```bash
# Controlled listener contrast: owned service only; restore on normal/error exit.
(
  set -euo pipefail
  service=azure-dnat-fixture.service
  sudo /usr/local/bin/dnat-ready
  restore_fixture() {
    status=$?
    trap - EXIT HUP INT TERM
    if sudo systemctl start "$service"; then
      if sudo /usr/local/bin/dnat-ready; then
        printf 'Owned fixture restored and locally ready.\n'
      else
        printf 'ERROR: fixture started but readiness failed; investigate before continuing.\n' >&2
        status=1
      fi
    else
      printf 'ERROR: owned fixture restart failed; manual recovery required.\n' >&2
      status=1
    fi
    exit "$status"
  }
  trap restore_fixture EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  sudo systemctl stop "$service"
  if sudo systemctl is-active --quiet "$service"; then
    printf 'ERROR: fixture remains active; aborting contrast.\n' >&2
    exit 1
  fi
  printf 'Run the listener-unavailable probe from C now. Press Enter to restore; auto-restore after 60 seconds.\n'
  if read -r -t 60 _; then
    :
  else
    printf 'Contrast window ended; attempting restoration.\n'
  fi
)
```

While that block waits, from C run `./scripts/client-probe.sh listener-unavailable "$P" "$ALLOWED" "$C"`. Then press Enter in B's session. A matching NAT row can still appear despite no valid application response, distinguishing a policy match from listener success. The trap attempts restart/readiness on normal exit, command failure, timeout/EOF or catchable interruption. **It cannot guarantee recovery after SIGKILL, VM/host failure or loss of execution.** If restoration is not confirmed, reconnect and recover only the owned unit:

```bash
sudo systemctl start azure-dnat-fixture.service
sudo /usr/local/bin/dnat-ready
```

Require successful local readiness and a fresh external positive before declaring restoration. Preserve failed cleanup status rather than continuing as if it passed. Never kill an unknown process or report a failed request as a new firewall Deny.

### Remove workload /0: return-path contrast

Change only `enable_default_route=false`. Review/authorize a plan deleting the standalone `azurerm_route.backend["default"]`; the route table remains attached. Recollect effective routes and next hop to newly observed I, run a fresh positive and 8444 control. Expected: hub peering /16 still routes the DNAT response. Removing /0 need not break it. Explicit private-subnet mode and outbound NSG deny remain unchanged; no broad egress permission is added.

Restore `enable_default_route=true` through the reviewed owning configuration. Verify /0→current F is back, then rerun readiness/positive/negative control.

### Break the instance return path

Start with `publish_dnat=true`, `enable_default_route=true`, `return_route_blackhole=false`. Change only `return_route_blackhole=true`. The added route is **10.0.1.0/26 → None**, more specific than hub-peering /16. It covers all potential firewall instances, not a potentially changing I/32. Bastion's distinct 10.0.2.0/26 remains reachable.

After review/authorization, confirm B's effective route/next hop for I selects that blackhole. From C run `./scripts/client-probe.sh return-blackhole "$P" "$ALLOWED" "$C"`. No normal application response is expected; an ingress NAT match can still be logged. For a fresh TCP connection, the blackhole can drop B's SYN-ACK before HTTP is sent, so a backend HTTP case/journal row is normally absent and is not required evidence. Use the effective None route, NAT match and optional bounded handshake capture. This is a **return-routing failure**, not a DNAT-policy Deny or a route to public C. Restore `return_route_blackhole=false`, confirm the /26 is removed, then re-establish local readiness, actual I return route, positive and 8444 control. Mark rollback complete only with restored evidence.

### Withdraw publication without deleting the lab

Change only `publish_dnat=false` and review/authorize removal of this module's `test-rules` collection group. It is the only group in this dedicated policy. Do not add a later network Deny as a substitute. Recollect policy groups to confirm absence, then from C:

```bash
./scripts/client-probe.sh publication-withdrawn "$P" "$ALLOWED" "$C"
```

Verify a fresh request no longer reaches the fixture. This does not prove existing sessions were immediately terminated; verify any required shutdown behavior separately. Resource billing continues. To republish, reapprove the exact current C/32 and mapping, set `publish_dnat=true`, review the plan and repeat the full acceptance sequence. No cloud action is authorized by this document itself.

## Cleanup after explicit deletion approval

Save evidence outside the VM. Verify the actual owning state/subscription and that this dedicated RG contains only this lab. Never destroy shared native-hub/atlas resources.

```bash
RG=$(terraform output -raw resource_group_name)
FW_ID=$(terraform output -raw firewall_id)
SUBSCRIPTION_ID=$(printf '%s' "${SUBSCRIPTION_ID:?Set the approved subscription UUID}" | tr '[:upper:]' '[:lower:]')
STATE_SUBSCRIPTION_ID=$(printf '%s' "$FW_ID" | cut -d/ -f3 | tr '[:upper:]' '[:lower:]')
if [[ "$STATE_SUBSCRIPTION_ID" != "$SUBSCRIPTION_ID" ]]; then
  printf 'Stop: Terraform firewall state belongs to a different subscription.\n' >&2
  exit 1
fi
terraform plan -destroy -out=destroy.tfplan
terraform show -no-color destroy.tfplan
```

After deletion is approved, execute the reviewed destroy plan using the approved workflow. Preserve state on failure. Then verify:

```bash
terraform state list
az group exists --name "$RG" --subscription "$SUBSCRIPTION_ID"
```

Expect empty state and false only after completed deletion. Check for orphaned Firewall, Bastion, public IPs, VM/OS disk, policy, peerings, workspace and network resources. The RG deletion guard remains enabled; do not disable it to remove unknown contents. Do not permanently purge logs as incidental cleanup. Billing views may lag. Stopping only the VM or withdrawing DNAT is not full cleanup.

## Limits and troubleshooting

- No SSH: check Bastion service/required NSG, both peerings, B's Bastion-source22 rule and approved key/host identity. Do not expose public SSH.
- Positive fails: check actual C/P, publication flag/mapping, listener readiness, translated-source NSG, peerings and route to observed I. Missing NAT logs can be lag or no match; a NAT match alone is not origin success.
- Peer identity unexpected: separate local readiness from the external case, inspect exact policy/topology, and do not force evidence to match assumptions. Client XFF is not trusted identity.
- NAT match but response absent: inspect owned listener/guest firewall/NSG and return route to I. Backend /0 does not override a more-specific hub/blackhole prefix.
- Negative succeeds: recheck actual public source, all DNAT groups/rules, public P/port, fresh session and policy attachment. Do not claim configured state equals deployed state.
- Source IP changes: stop and review the specific new /32; do not widen scope to make the test work.
- Missing extensions, governance or capacity: report the exact blocker; do not silently install software, disable policy, change region/subscription or add egress.

This lab does not establish production authentication, TLS/WAF protection, resilience, scale, complete exfiltration prevention, hairpin/private-IP DNAT, hybrid/vWAN behavior or forced tunneling support. Real forced tunneling is excluded from this public-DNAT design; merely having a management NIC is a different configuration. All services and public exposure should be short-lived. No update/agent Internet allow is included, so do not operate the VM long-term without a separately reviewed maintenance design. [Forced-tunneling distinction](https://learn.microsoft.com/en-us/azure/firewall/forced-tunneling)

Official sources and validation limits: [SOURCES.md](SOURCES.md), [validation/STATUS.md](validation/STATUS.md).
