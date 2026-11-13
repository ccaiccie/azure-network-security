# Azure Firewall private east-west inspection lab

**Independent draft, 4 November 2026. No Azure deployment, Terraform plan/apply/destroy, cloud listener check, packet capture or Azure traffic test has been performed.** Local-only check results are in [validation/STATUS.md](validation/STATUS.md). Terraform/provider validation remains outstanding.

This module implements the **two-spoke HTTP baseline** from the [scenario 02 guide](../azure-02-east-west-inspection-guide.md). It does not modify the published native-hub repository or reuse its resources. App VM A reaches HTTP fixture B through a hub firewall using network rules, preserving A's private source address. B's response selects the same firewall path.

The guide's published database drawing uses B=10.20.1.20 and TCP5432. This implementation instead uses **B=10.20.1.10 and TCP8080**, with a real local-readiness requirement for TCP8081 and reverse-initiation tests. It deploys no PostgreSQL service. An optional **same-VNet C variant is implemented** behind `enable_same_vnet=true`, with its own private subnet/VM, two /24 inspection routes, scoped rules, fixtures and probes. It has not been deployed or Azure-tested. Its separate setup, evidence and rollback are below.

## Topology, names and actual outputs

| Component | Configuration |
|---|---|
| Resource group | `inspection-east-west` by default; new/dedicated, configurable |
| Hub | `hub`, `10.0.0.0/16` |
| Firewall subnet | `AzureFirewallSubnet`, `10.0.1.0/26` |
| Firewall | `lab-firewall`, Standard, standalone `east-west-policy` |
| Firewall IP F | Computed output; illustrative `10.0.1.4` is never hardcoded |
| App spoke | VNet `app`, `10.10.0.0/16`; subnet `workload`, `10.10.1.0/24` |
| App endpoint A | VM `app`, NIC `app-nic`, `10.10.1.10`, listener TCP8080 |
| Server spoke | VNet `db`, `10.20.0.0/16`; subnet `workload`, `10.20.1.0/24` |
| Server endpoint B | VM `db`, NIC `db-nic`, `10.20.1.10`, listeners TCP8080/8081 |
| Optional C endpoint | VM `c`, NIC `c-nic`, `10.10.2.20`; subnet `same-vnet`, `10.10.2.0/24`, in the existing `app` VNet; listeners TCP8080/8081 |
| Workload route tables | `app-inspect`, `db-inspect`; `c-inspect` only when C is enabled |
| Management | `AzureBastionSubnet`, `10.0.2.0/26`; `ew-bastion`, Standard |
| Logs | Dedicated `east-west-logs`, 30-day retention |

Outputs include actual resource group/location, firewall identity/private/public addresses and policy ID; all enabled VM/NIC IDs/private IPs/VNet and subnet names/route table IDs through `workloads`; separate `app_vm_id`/`db_vm_id` and optional `c_vm_id`; Bastion name; admin user; Log Analytics ARM ID and customer GUID; image version and experiment flags. No secret is intentionally output. Terraform state itself remains sensitive.

There are four hub/spoke peering objects, each with VNet access/forwarded traffic enabled and gateway flags disabled. **There is no direct app-db peering.** All enabled private workload subnets explicitly disable default outbound access, all workload NICs lack public IPs, and no NAT Gateway/outbound load balancer/private endpoint/gateway exists. No customer NSG or route-to-self table is placed on `AzureFirewallSubnet`.

The firewall's required public IP and Bastion's separate public IP do not appear in the private A-to-B tuple. The management path is `operator HTTPS → Bastion → private spoke SSH`. Management access is not an east-west inspection test.

## Exact routing and security policy

Baseline Terraform variables:

```hcl
explicit_remote_routes = true
return_route_blackhole = false
enable_same_vnet = false
same_vnet_return_route_enabled = true
```

| Subnet route table | Destination | Next hop |
|---|---|---|
| `app-inspect` | `10.20.0.0/16` | VirtualAppliance F |
| `app-inspect` | `0.0.0.0/0` | VirtualAppliance F |
| `db-inspect` | `10.10.0.0/16` | VirtualAppliance F |
| `db-inspect` | `0.0.0.0/0` | VirtualAppliance F |

The remote /16 is more specific than /0. At the hub, destination-spoke peering supplies onward reachability. A route chooses the next hop but leaves the packet addressed to B, not F. The Linux guest gateway may remain its Azure subnet gateway; do not rewrite it to F. Peering alone is nontransitive. The hub-side routing explanation is a design deduction, not a promised internal managed-firewall-NIC query.

Firewall rule collection group `east-west-rules`, priority 300:

| Collection / priority | Action | Rule | Source | Destination / TCP port |
|---|---|---|---|---|
| `allow-private-fixture` / 100 | Allow | `allow-app-to-test` | A/32 | B/32:8080 |
| `deny-negative-fixtures` / 200 | Deny | `deny-reverse-new` | B/32 | A/32:* |
| Same Deny collection | Deny | `deny-app-alternate-port` | A/32 | B/32:8081 |

There are no application, DNAT, broad internet or AzureCloud Allow rules in the workload firewall policy. No custom private SNAT ranges or parent policy are configured. Under default private-range network-rule behavior, B sees A's original private address. The named reverse Deny concerns **new** B→A connections; it does not override return state for the allowed A→B session. State still needs B's return route. [Private SNAT behavior](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range), [Rule order and state](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)

The workload subnet NSGs deliberately permit each tested connection to reach the firewall decision:

| NSG | Direction | Original packet source → destination | TCP ports |
|---|---|---|---|
| `app-nsg` | Outbound | A → B | 8080,8081 |
| `db-nsg` | Inbound | A → B | 8080,8081 |
| `db-nsg` | Outbound | B → A | 8080 |
| `app-nsg` | Inbound | B → A | 8080 |

Those rules use priority 100. Both workloads also allow inbound SSH only from `10.0.2.0/26` at 110, and DNS UDP/TCP53 only to computed F at 200/201. `AzurePlatformDNS` is denied at 210; remaining new inbound/outbound traffic is denied at 4000. Stateful replies need no broad ephemeral-port exceptions. There are no additional NIC NSGs.

No workload Internet/AzureCloud Allow is configured. DNS proxy is available and workload DNS points to F, but the HTTP tests use literal private IPs and do not rely on DNS. Proxy DNS queries can still reach the upstream resolver, so this is not zero communication or a comprehensive DNS-exfiltration policy. Do not block all of platform address 168.63.129.16, which also supports other platform functions.

## Prerequisites, cost and reproducibility

Before any deployment, approve the subscription, dedicated resource scope, actual region, services, spend and cleanup time.

- Terraform `>=1.9,<2.0`; pinned AzureRM **5.12.0**; recent Azure CLI with official Bastion extension; local OpenSSH, Bash and Python 3. No tool was installed while drafting.
- An existing authorized Azure login/credential method and SSH key pair. Supply **only the public key** to Terraform; private key stays on the workstation. No credentials, identity grants or role assignments are created by this module.
- Required resource providers already registered: Microsoft.Resources, Microsoft.Network, Microsoft.Compute, Microsoft.OperationalInsights, Microsoft.Insights. Automatic AzureRM registration is disabled. Any missing registration is a separate authorized subscription change.
- Permissions to create/delete only the new lab scope, read effective routes/NSGs, use Bastion and query logs. Bastion key-based access needs reads on target VM, NIC and Bastion, plus the local SSH key. No public SSH fallback or broad Run Command network permission is supplied.
- Approved region with Firewall Standard, Bastion Standard and two chosen x64 VM allocations available, or three when C is enabled. `eastus`/`Standard_B1s` are sample values, not capacity guarantees. Check quota, governance requirements and current limitations.
- A **concrete approved** Canonical `ubuntu-24_04-lts:server` image version. `image_version` has no default and rejects `latest`. The example placeholder is intentionally invalid. The image must already contain Python 3, curl, iproute2 (`ip`, `ss`), systemd, cloud-init and Bash. No package download is attempted.
- Azure Policy must permit separate NSG/route-table subnet associations, the required public service IPs and supplied tags/images. Adapt to organizational policy with reviewed provider-supported atomic subnet settings if necessary; never disable policy to make the sample work.
- An existing authorized regional Network Watcher is optional for next-hop diagnostics. The template does not create one or auto-install a guest capture utility.

Read-only operator checks, after authorized sign-in:

```bash
az account show --query '{subscription:id,tenant:tenantId,name:name}' -o json
az provider show --namespace Microsoft.Network --query registrationState -o tsv
az provider show --namespace Microsoft.Compute --query registrationState -o tsv
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
az provider show --namespace Microsoft.Insights --query registrationState -o tsv
az vm list-skus --location eastus --size Standard_B1s --all -o table
az vm image list --location eastus --publisher Canonical \
  --offer ubuntu-24_04-lts --sku server --all -o table
```

**This is not a free lab.** Budget for Firewall Standard provisioned time/data, Bastion Standard with two scale units, two VMs/OS disks (three with C), two Standard public IPv4 addresses, peering traffic and Log Analytics ingestion/retention. Firewall and Bastion remain billable while idle or when only the VMs are stopped. There is no daily log cap, which could suppress needed evidence; control duration and review approved cost alerts instead. Current regional/account/currency pricing must be obtained before deployment; no fixed cost or spending cap is claimed. [Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/), [Bastion pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/), [Pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)

A genuine `.terraform.lock.hcl` is **not supplied**, because provider initialization did not run. Retain and review the lock generated by an approved initialization; never invent hashes. Protect local state/plans, which may include provider-returned workspace keys even with workspace local authentication disabled. Use an approved encrypted/locked backend for team use through a separately reviewed setup.

## Prepare and review, without deploying

All commands below are **future authorized operator instructions**, not claimed executions.

```bash
cd lab  # From the scenario package root
cp terraform.tfvars.example terraform.tfvars
# Edit subscription, approved region/image_version, ownership and variant flags.
# Choose enable_same_vnet before the first deployment; changing it can replace A/B.
export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"
./scripts/check-local.sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```

The local Python tests bind only loopback ports 8080/8081 and an ephemeral loopback port, close them afterward and make no Azure/external requests. If a port is occupied, do not kill its owner; report the local test conflict. They verify fixture behavior, selected probe paths and control-plane collection using fake Azure/Terraform commands, not Azure routes or systemd boot startup. The supplied seven Terraform mock-plan runs assert exact route/NSG test tuples, firewall names/priorities/tuples, route-experiment flags and C resource/route invariants. Known-value route and NSG specifications feed the actual dynamic resource blocks; focused source checks guard that connection. These mock runs remain unexecuted until Terraform/provider initialization is available.

`init -backend=false` avoids backend initialization but can download provider packages. It is not inherently offline. A true offline initialization needs an already approved populated mirror, e.g. `-plugin-dir=/approved/provider-mirror`. All supplied Terraform test runs are **mocked and plan-only**; never remove the mock to run them against a real subscription unintentionally.

Prepare a real deployment plan only after prerequisites are settled:

```bash
terraform plan -out=lab.tfplan
terraform show -no-color lab.tfplan
```

Review actual identity, region, scope, spend, pinned image/provider, baseline flags, no workload public IP, only the two intended service public IPs, NSG/route associations, four peerings and private network rules. **Stop for deployment authorization.** An authorized operator may execute the reviewed plan through the approved workflow; no deployment is executed by this draft. Successful provisioning alone does not establish service or traffic readiness.

## Private management and owned fixtures

On the local management workstation, not Cloud Shell:

```bash
RG=$(terraform output -raw resource_group_name)
BASTION=$(terraform output -raw bastion_name)
USER_NAME=$(terraform output -raw admin_username)
APP_ID=$(terraform output -raw app_vm_id)
DB_ID=$(terraform output -raw db_vm_id)

# App session:
az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$APP_ID" \
  --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
# Separate local terminal, db session:
az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$DB_ID" \
  --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
```

Verify host keys using the approved process. Never disable host-key checking or expose public SSH. Bastion's management subnet has all its required service NSG rules, including its own Azure control-plane/internet dependencies; these are **not** workload egress permissions. No workload inspection UDR is attached to Bastion. [Bastion NSG rules](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg), [Native SSH/tunnel support](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)

Azure Run Command is not the access path: its results need outbound TCP443 to Azure public endpoints. Missing output can occur even if the guest command executed, and adding a broad AzureCloud Allow would materially change this design. [Run Command dependencies](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)

Cloud-init writes:

- `/opt/azure-ew-lab/server.py`: bounded fixed JSON response; no directory or file serving.
- `/etc/systemd/system/azure-ew-fixture@.service`: owned template with DynamicUser, read-only system protection and journal logs.
- `/etc/azure-ew-lab.env` and `.json`: nonsensitive private IP/role configuration.
- `/usr/local/bin/ew-ready` and `/usr/local/bin/ew-probe`: evidence helpers.

It enables A's `azure-ew-fixture@8080.service`, and B's (and optional C's) `@8080` and `@8081` services, bound to their own private IPs. It then records local readiness in `/var/log/azure-ew-readiness.log`. No arbitrary process is killed, no package is fetched, and no cross-spoke probe runs automatically. Service startup errors must be investigated, never disguised with broad egress changes.

## Exact demo and evidence sequence

### 1. Establish actual configuration

On the management workstation:

```bash
./scripts/collect-control-plane.sh
terraform output experiment_settings
```

Retain both effective NIC route tables/NSGs, both subnet associations/private-outbound settings, all four Connected peerings, actual F, policy/rules, no SNAT override/parent policy, resource-specific diagnostics and running VM state. Two-spoke baseline flags must be `explicit_remote_routes=true`, `return_route_blackhole=false`, `enable_same_vnet=false`, `same_vnet_return_route_enabled=true`. The collector automatically includes C when enabled. A configured route alone is not proof that the workload uses it.

Optional next-hop checks, only with an existing authorized Network Watcher:

```bash
az network watcher show-next-hop -g "$RG" --vm app --nic app-nic \
  --source-ip 10.10.1.10 --dest-ip 10.20.1.10 -o json
az network watcher show-next-hop -g "$RG" --vm db --nic db-nic \
  --source-ip 10.20.1.10 --dest-ip 10.10.1.10 -o json
```

Both should identify VirtualAppliance and actual F. Missing Watcher means **NOT RUN**, not permission to create it. A next-hop result is route evidence, not firewall/application success.

### 2. Verify all three listeners locally before negative probes

In **each VM's** Bastion session:

```bash
cloud-init status --wait
sudo cat /var/log/azure-ew-readiness.log
sudo /usr/local/bin/ew-ready
sudo ss -lntp
sudo systemctl status 'azure-ew-fixture@8080.service' --no-pager
# On db B only:
sudo systemctl status 'azure-ew-fixture@8081.service' --no-pager
```

`ew-ready` verifies the correct local IP, owned service activity and fixed-response HTTP200/JSON identity at every expected local port. It bypasses HTTP proxies and retries briefly for initial bind readiness. Success means **local readiness only**. Preserve a fresh A:8080 and B:8080/8081 readiness record with UTC time. If any listener is missing, the corresponding remote denial is **inconclusive** until repaired under the authorized configuration.

For direct curl equivalents:

```bash
# A:
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.10.1.10:8080/ready-local
# B:
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.20.1.10:8080/ready-local
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.20.1.10:8081/ready-local
```

### 3. Positive, alternate-port negative, new-reverse negative, positive again

In **A**:

```bash
/usr/local/bin/ew-probe positive
/usr/local/bin/ew-probe alternate-port
```

In **B**, after verifying A's listener:

```bash
/usr/local/bin/ew-probe reverse-new
```

Back in **A**:

```bash
/usr/local/bin/ew-probe positive
```

Each call creates a unique case ID and evidence directory under `~/ew-evidence/`, records UTC time, fresh connection local/remote IP/port, headers/body/stderr and curl status. It uses `curl -q` first to ignore `.curlrc`, IPv4, HTTP1.1, no proxy or redirect following. Positive fixture identity is checked but never substitutes for route/firewall evidence. The helper exits normally after recording a negative curl result; its shell exit is not a pass verdict.

Expected outcomes, **not captured Azure results**:

| Case | Actual endpoint | Pass requires |
|---|---|---|
| Positive A→B | B:8080 | HTTP200, JSON `peer_ip=10.10.1.10`, `server_ip=10.20.1.10`, port8080, matching case, selected F routes and `allow-app-to-test` Allow |
| Alternate port A→B | B:8081 | Recently locally verified listener, permitting effective NSGs, no successful origin response and `deny-app-alternate-port` Deny |
| New reverse B→A | A:8080 | Recently locally verified listener, permitting effective NSGs, no successful origin response and `deny-reverse-new` Deny |
| Positive after reverse deny | B:8080 | Same positive criteria; illustrates returning state differs from new reverse initiation |

Do not prescribe a specific timeout/reset/curl code for negatives. A failed curl without a matching named Deny can be routing, NSG, listener or host failure. A successful server response plus unchanged private source can still occur over a direct path, so route and firewall evidence are both required.

### 4. Server records and firewall decisions

Inside B, for the positive test's UTC window:

```bash
sudo journalctl -u azure-ew-fixture@8080.service --since '10 minutes ago' \
  --utc --no-pager -o cat
sudo journalctl -u azure-ew-fixture@8081.service --since '10 minutes ago' \
  --utc --no-pager -o cat
```

Inside A, inspect `azure-ew-fixture@8080.service` for the reverse-test window. Readiness calls legitimately appear in logs; correlate the **case ID**, not merely the presence of a request. Absence of a server row alone is not a firewall-deny proof.

`queries/network.kql` selects A/B and optional C private endpoints and actual firewall resource ID. Replace `FIREWALL_RESOURCE_ID`, then query the dedicated workspace Logs UI. With an already installed/approved Log Analytics CLI extension:

```bash
FW_ID=$(terraform output -raw firewall_id)
WORKSPACE=$(terraform output -raw workspace_customer_id)
mkdir -p evidence
sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/network.kql > evidence/network.kql
az monitor log-analytics query --workspace "$WORKSPACE" \
  --analytics-query "$(cat evidence/network.kql)" -o json > evidence/network-decisions.json
```

Correlate UTC time, A/B addresses, observed source port, destination port and exact rule. `queries/decisions.kql` also includes threat-intelligence decisions if needed. Log ingestion can lag and initial activation can take up to 30 minutes; empty immediate queries are **inconclusive**. Normal network logs are not guaranteed complete bidirectional packet captures. No separate reverse Allow row is required to establish permitted response state, and no NAT-rule log is expected in this no-NAT private flow. [Monitoring](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall), [Network table schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule)

Optional endpoint captures are **not automated** and require an already installed approved tcpdump. In separate endpoint sessions, use a bounded capture around one positive request:

```bash
sudo timeout 25 tcpdump -ni any -s 96 \
  'tcp and host 10.10.1.10 and host 10.20.1.10 and port 8080' \
  -w /tmp/ew-positive-headers.pcap
```

Use separate files per host. These captures can show address/tuple visibility but do not prove invisible Azure fabric routing by themselves. Snapshot length reduces payload collection but may still capture some application bytes. Send only synthetic fixture traffic.

### 5. Save evidence and record outcomes

Use [RESULTS.template.md](RESULTS.template.md). Every row starts **NOT RUN**. Retain configuration, readiness, all four probe results, server rows and matching firewall rows together. Redact subscription/tenant identifiers, private topology and SSH details before publication; never share state or binary plans as demo evidence.

To transfer files, use a Bastion tunnel from a local terminal (keep it open):

```bash
az network bastion tunnel -g "$RG" -n "$BASTION" --target-resource-id "$APP_ID" \
  --resource-port 22 --port 50022
# Another terminal, preserving host-key verification:
scp -P 50022 -i "$HOME/.ssh/your-approved-key" -r \
  "$USER_NAME@127.0.0.1:/home/$USER_NAME/ew-evidence" ./evidence/app-guest
```

Repeat with DB_ID and a different local port/path for B. `az network bastion ssh` does not itself transfer files. Export only authorized journal/readiness evidence; do not broaden file permissions or copy unrelated logs.

## Implemented route experiments and rollback

These are **optional, disruptive configuration changes**, not baseline traffic tests. No experiment or rollback has been executed. Review authorization and resource ownership before each change, and preserve the baseline evidence/state first.

### Default-route-only variant

Set `explicit_remote_routes=false` while retaining `return_route_blackhole=false`. Review a Terraform plan containing only the intended route removals, then use the authorized deployment workflow. Recollect both effective routes/next hops and repeat baseline tests.

Removing remote /16 routes does **not** guarantee failure: each /0 still points to F, and can carry the flow absent more-specific competitors. Do not invent which None routes exist. No direct app-db peering is added by this switch.

### Deterministic return-route blackhole

Starting from baseline, set `return_route_blackhole=true`. This adds only `10.10.1.10/32 → None` on `db-inspect`; it overrides both the remote /16 and /0 for traffic toward A. It leaves Bastion's distinct hub path available. Review/authorize the changed plan before execution.

Expected experiment evidence: B's next-hop lookup for A reports None; a new A→B positive request cannot complete normally because B cannot route its response to A. An ingress firewall Allow can still appear. This is a **routing failure**, not a new firewall denial or a direct-path bypass. Do not claim a particular curl error is the sole proof.

### Restore exact baseline

1. Restore `explicit_remote_routes=true` and `return_route_blackhole=false` in the owning `.tfvars`; remove any one-off CLI overrides that would reintroduce the experiment.
2. Review the plan and confirm the experimental /32 is removed and both remote /16 routes are restored. Execute only through the approved workflow. Do not leave permanent CLI drift.
3. Preserve and verify service ownership; repair only the named lab service/configuration if needed. Do not kill an unknown 8080 process.
4. Recollect both effective route tables/next hops and NSGs, then rerun readiness on both VMs, positive, alternate negative, reverse negative and positive again.
5. Mark rollback complete only when the documented baseline evidence is restored.

### Optional same-VNet C variant: separate executable configuration

Choose these settings **before first deployment** for a combined A/B plus A/C lab:

```hcl
explicit_remote_routes = true
return_route_blackhole = false
enable_same_vnet = true
same_vnet_return_route_enabled = true
```

C adds a third private VM (`c`), NIC (`c-nic`), subnet (`same-vnet`, `10.10.2.0/24`) in the **existing app VNet**, `c-nsg`, `c-inspect` and their subnet associations. Its fixed IP is `10.10.2.20`. It adds no VNet, peering, public IP or outbound Internet permission. The two-spoke A/B tests remain available unchanged.

**Changing `enable_same_vnet` changes cloud-init data for A/B as well as adding/removing C; AzureRM can replace existing A/B VMs.** Save evidence first, review actual replacement/data-loss consequences, and obtain approval for the changed plan. Do not enable/disable it as a supposedly harmless live routing toggle. The separate route flags do not enter cloud-init data.

Additional route entries:

| Table | Route name | Destination | Next hop |
|---|---|---|---|
| `app-inspect` | `same-vnet-forward` | `10.10.2.0/24` | VirtualAppliance F |
| `c-inspect` | `same-vnet-return` | `10.10.1.0/24` | VirtualAppliance F |
| `c-inspect` | `default` | `0.0.0.0/0` | VirtualAppliance F |

The A/C /24 UDRs beat the app VNet's local `10.10.0.0/16` system route. A /0 alone does not force same-VNet inspection. Both directions must select F; the hub's app-VNet peering supplies onward reachability. Do not set a route to F on the firewall's own subnet.

The same `east-west-rules` group and collections add:

| Collection / priority | Rule | TCP tuple / action |
|---|---|---|
| `allow-private-fixture` / 100 | `allow-app-to-same-vnet` | A/32 → C/32:8080 Allow |
| `deny-negative-fixtures` / 200 | `deny-same-vnet-alternate-port` | A/32 → C/32:8081 Deny |
| `deny-negative-fixtures` / 200 | `deny-same-vnet-reverse-new` | C/32 → A/32:* Deny for new initiation |

A's NSG adds priority101 outbound A→C TCP8080/8081 and inbound C→A TCP8080. C's NSG has priority100 inbound A→C TCP8080/8081 and outbound C→A TCP8080. C inherits the same Bastion-only SSH, DNS-to-F, direct-platform-DNS deny and remaining-traffic deny pattern. Negative ports are deliberately permitted by NSGs so the firewall can make the named decision.

After the reviewed configuration has been separately authorized and deployed, establish C's private management session:

```bash
# Management workstation, with RG/BASTION/USER_NAME from the management section:
C_ID=$(terraform output -raw c_vm_id)
az network bastion ssh -g "$RG" -n "$BASTION" --target-resource-id "$C_ID" \
  --auth-type ssh-key --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
```

Inside **C**, verify both owned listeners before any remote-negative claim:

```bash
cloud-init status --wait
sudo cat /var/log/azure-ew-readiness.log
sudo /usr/local/bin/ew-ready
sudo ss -lntp
sudo systemctl status azure-ew-fixture@8080.service azure-ew-fixture@8081.service --no-pager
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.10.2.20:8080/ready-local
curl -q -4 --noproxy '*' --connect-timeout 3 --max-time 5 http://10.10.2.20:8081/ready-local
```

Also repeat A's `ew-ready` for reverse-test readiness. On the management workstation, run `./scripts/collect-control-plane.sh` and retain A/C effective routes and NSGs, both subnet associations, the new policy rules and actual C identity. Optional existing-Watcher checks:

```bash
az network watcher show-next-hop -g "$RG" --vm app --nic app-nic \
  --source-ip 10.10.1.10 --dest-ip 10.10.2.20 -o json
az network watcher show-next-hop -g "$RG" --vm c --nic c-nic \
  --source-ip 10.10.2.20 --dest-ip 10.10.1.10 -o json
```

Both should select VirtualAppliance F. Missing diagnostics remain NOT RUN. In **A**, then **C**, then **A** again:

```bash
# In A:
/usr/local/bin/ew-probe same-positive
/usr/local/bin/ew-probe same-alternate-port
# In C, a separate new connection:
/usr/local/bin/ew-probe same-reverse-new
# Back in A:
/usr/local/bin/ew-probe same-positive
```

| C case | Acceptance evidence, not an observed result |
|---|---|
| A→C:8080 | HTTP200; JSON role `c`, `peer_ip=10.10.1.10`, `server_ip=10.10.2.20`, port8080 and matching case; both /24 F routes; matching `allow-app-to-same-vnet` Allow |
| A→C:8081 | Fresh C:8081 local readiness, permitting effective NSGs, no successful response and matching `deny-same-vnet-alternate-port` Deny |
| New C→A:8080 | Fresh A:8080 local readiness, permitting effective NSGs, no successful response and matching `deny-same-vnet-reverse-new` Deny |
| A→C:8080 retest | Full positive evidence after the reverse-new denial |

On C, collect each owned unit's journal using the earlier `journalctl` commands; on A collect its 8080 journal for the reverse window. Reuse the KQL queries, which include C, and correlate UTC/tuple/source port with the exact named rule. Copy C evidence through its Bastion tunnel to a separate local folder if needed. **No source-preserving response alone proves a firewall path**, because a direct same-VNet route also preserves source.

### Optional C return-path asymmetry experiment and rollback

Keep `enable_same_vnet=true`, `explicit_remote_routes=true`, `return_route_blackhole=false`. Change only `same_vnet_return_route_enabled=false` in the owning variables. Review a plan showing removal of **only C's `10.10.1.0/24` return UDR**, then use the separately authorized workflow.

C's remaining /0→F loses to its local `10.10.0.0/16` route for A; A's `10.10.2.0/24`→F route remains. Verify the actual effective routes/next hops. This is an **asymmetric route experiment**, not a deterministic timeout or named-firewall-deny test. A particular response/failure depends on state and path handling; it cannot by itself prove correct inspection. Record what actually happens and do not accept this configuration as the inspected baseline. Do not reuse the B-only /32 blackhole flag as a C experiment.

To restore the **C-enabled baseline**, set `same_vnet_return_route_enabled=true` while retaining `enable_same_vnet=true`, `explicit_remote_routes=true`, `return_route_blackhole=false`. Review/authorize restoration of C's /24, collect both A/C next hops and NSGs, repeat A/C readiness and all four C probe calls, and confirm A/B baseline still works. Mark rollback complete only after the full evidence is restored.

To return to the **two-VM baseline**, preserve evidence and separately review/authorize `enable_same_vnet=false`; this removes C resources and can replace A/B due to changed cloud-init. Re-run the original A/B acceptance sequence afterward. Cleanup of the whole lab is distinct from either rollback.

## Cleanup after explicit deletion approval

Save the evidence, verify the actual owning Terraform state/subscription and confirm the group contains only this lab. Do not destroy shared atlas resources. Review:

```bash
RG=$(terraform output -raw resource_group_name)
terraform plan -destroy -out=destroy.tfplan
terraform show -no-color destroy.tfplan
```

After deletion is approved, execute the reviewed destroy plan through the approved workflow. Preserve state if cleanup fails. Then verify:

```bash
terraform state list
az group exists --name "$RG"
```

Expect empty state and `false` only after all deletion completes. Inspect for orphaned Firewall, Bastion, all enabled VM/disks (including C), public IPs, policy, peerings, tables and workspace resources. The resource-group deletion guard is deliberately enabled; do not disable it to delete unknown contents. Stopping only the VMs is not cleanup. Do not permanently purge soft-deleted workspace data as an incidental action. Billing views can lag behind deletion.

## Limits and troubleshooting

- **No SSH:** inspect Bastion service status, its full mandatory NSG rules, the four peerings, workload Bastion-source TCP22 rule and key/host identity. Do not add a public workload IP or firewall DNAT.
- **Fixture not ready:** inspect cloud-init, `systemctl status` and that unit's journal. Local JSON identity must match the expected role/IP/port before negative tests count.
- **Positive fails without a firewall row:** check effective routes and NSGs before changing policy. Peering is not transitive; unattached tables have no effect.
- **Firewall Allow, no response:** inspect B's listener, guest firewall and return route. State cannot manufacture return routing.
- **Negative succeeds:** verify new connections, actual rule collection/policy/parent, actual next hops and possible bypasses. Do not assume the deployed policy matches HCL.
- **Missing logs:** check Dedicated diagnostics, actual workspace/firewall identity and ingestion lag. Absence is not a verdict.
- **Denied provisioning:** report the exact capacity/quota/policy issue; do not disable governance or change subscriptions silently.

This lab does not prove production resilience, scale, universal east-west segmentation, decrypted HTTP inspection, TLS, database security, IPv6, private endpoints, hybrid/vWAN behavior or complete exfiltration prevention. NSG state, firewall state, routes and applications are separate controls. All HTTP responses are synthetic and unencrypted. Threat intelligence is Alert for attributable teaching decisions, not a production recommendation. Most package/agent endpoints are not allowed; do not operate these VMs long-term without a separately reviewed maintenance design.

Current official references and version-review limits are in [SOURCES.md](SOURCES.md).
