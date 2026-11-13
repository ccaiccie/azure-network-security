# Azure hub-spoke firewall egress lab

**Independent implementation draft, 4 November 2026. No cloud resource was created, no Terraform plan/apply/destroy was run, and no Azure traffic result is claimed.** See [validation/STATUS.md](validation/STATUS.md) for exactly what was and was not checked.

This lab makes one private Linux VM send selected IPv4 TCP/443 traffic through an Azure Firewall Standard in a peered hub. It includes a separate Bastion management path, a dedicated logging workspace, scripts, queries, and cleanup instructions. It does not modify or depend on an existing repository, hub, workspace, or subscription configuration.

## Two scenarios, deliberately different

| Scenario | Selection | What the firewall permits | Important limit |
|---|---|---|---|
| **Primary: network rules** | `policy_mode = "network"` (default) | TCP/443 to IPs obtained from `www.microsoft.com` and `api.ipify.org` | DNS-derived IP allowlisting, not HTTP Host/SNI enforcement. An unrelated hostname sharing an allowed IP may work. |
| Optional: application rules | `policy_mode = "application"` | HTTPS/443 for those exact FQDNs via application proxy | Standard does not decrypt HTTPS URL paths or content. |

The Terraform configuration emits **one collection type at a time**. Never layer a broad TCP/443 network Allow on top of the application scenario. Network rules are processed before application rules regardless of numerical priorities. [Rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)

The primary scenario matches the network-rule packet/SNAT model in the [companion diagrams](../diagrams/README.md) and [conceptual guide](../azure-firewall-hub-spoke-egress-guide.md). The conceptual guide's application-rule example corresponds to the optional application scenario. Shared address plans do not make these policies equivalent. Microsoft recommends application rules for HTTP/S hostname restrictions; network mode is retained here to teach network filtering, routing and SNAT. [Network-rule FQDN behavior](https://learn.microsoft.com/en-us/azure/firewall/fqdn-filtering-network-rules)

## Address plan and resources

| Resource | Name / address |
|---|---|
| Dedicated resource group | `rg-egress-demo` by default, configurable |
| Hub VNet | `vnet-hub`, `10.10.0.0/16` |
| Firewall subnet | `AzureFirewallSubnet`, `10.10.0.0/26` |
| Firewall and policy | `fw-egress`, `policy-egress`, Standard |
| Firewall private IP | Computed from the deployed firewall; **`10.10.0.4` is illustrative only** |
| Firewall public IP | `pip-fw-egress`, Standard static IPv4, allocated by Azure |
| Management subnet | `AzureBastionSubnet`, `10.10.1.0/26` |
| Bastion | `bastion-egress`, Standard, two scale units, separate `pip-bastion-egress` |
| Spoke VNet | `vnet-spoke`, `10.20.0.0/16`, DNS = actual firewall private IP |
| Workload subnet | `snet-workload`, `10.20.1.0/24`, `default_outbound_access_enabled = false` |
| VM / NIC | `vm-egress` / `nic-egress`, `10.20.1.4`, **no public IP** |
| Route table | `rt-spoke-egress`, `0.0.0.0/0 → VirtualAppliance <actual firewall IP>` |
| NSGs | `nsg-workload`, `nsg-bastion` |
| Logs | `law-egress`, 30-day retention, resource-specific firewall tables |

`main.tf`, `management.tf` and `diagnostics.tf` own all lab resources. The VM OS disk is created through the VM resource, not as an extra independent managed-disk resource. Both peering objects permit forwarded traffic. There is no VPN gateway, NAT Gateway, public VM endpoint, DNAT rule, service endpoint, private endpoint, or direct spoke-to-spoke peering. No NSG or default-to-self route is attached to the firewall subnet. [Firewall requirements](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq)

The guide's `198.51.100.80` and `203.0.113.10` are documentation-only addresses. They are **never** test URLs, configured public IPs, or expected deployment outputs. Use observed DNS addresses and actual Terraform outputs.

## Prerequisites and decisions before spending money

1. An explicitly approved Azure **public-cloud** subscription, region, spend, and deployment scope. `location = "eastus"` is a sample, not a capacity assertion. Check current firewall limitations, Bastion availability, VM quota and SKU availability. [Current limitations](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues)
2. Terraform `>= 1.9, < 2.0`, AzureRM **exactly `5.12.0`**, recent Azure CLI with the official `bastion` extension, OpenSSH client, Bash and Python 3 on the operator workstation. The provider pin is based on HashiCorp's 29 October 2026 release. Review a newer approved version deliberately rather than removing the pin. [Provider changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md)
3. Authorized Azure CLI sign-in, or an already approved noninteractive credential method. The template creates no credentials, role assignments or service principals. Supply an explicit subscription ID. **Automatic provider registration is disabled**: a subscription administrator must have already registered `Microsoft.Resources`, `Microsoft.Network`, `Microsoft.Compute`, `Microsoft.OperationalInsights` and `Microsoft.Insights`. Registering services is a separate subscription change, not something this draft performs. [AzureRM configuration](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
4. Permission to create/delete the dedicated resource group and its resources, plus read effective NIC routes/NSGs and query workspace logs. A narrowly scoped custom role is preferable in a managed environment. Bastion access requires reads on the VM, NIC and Bastion plus the VM's SSH key. No Entra VM login role is necessary for this local-key path. [Bastion roles](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)
5. An existing approved RSA or Ed25519 SSH public key and its private key kept on the workstation. Terraform receives **only the public key**. Do not create a private key with a Terraform resource or paste private credentials into this project.
6. A region-compatible Ubuntu image with `curl`, Python 3, `getent`, `ip`, `date`, and Bash preinstalled. `dig` is optional. Cloud-init writes the test script; it does not fetch packages. A missing utility is a prerequisite failure, not permission to add broad egress. Resolve and pin the actual image version before a reproducible deployment.
7. Approval for HTTPS test requests to the two default external hosts. `api.ipify.org` is a third-party public-IP echo service; replace it with an approved service or server-side access-log evidence if required. Endpoint availability is not verified by this draft. Changing hostnames requires corresponding test settings and expected results.
8. No conflicting Azure Policy requiring NSG/route-table association atomically at subnet creation. This template uses separate association resources. If such policy exists, adapt the configuration using the pinned provider's supported atomic fields and review it; do not disable organizational policy. The same applies to required tags, allowed regions, public-IP restrictions and image governance.

Read-only prerequisite examples, for an already authenticated operator:

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

VM SKU listing does not guarantee allocation capacity. Replace `eastus` consistently if a different region is approved. An existing regional Network Watcher is an **optional prerequisite** for the additional next-hop diagnostic; the template does not create one. Do not silently create a Network Watcher to make a read-only evidence step work.

## Cost and duration

**This is not a free lab.** Azure Firewall Standard and Bastion Standard accrue charges while provisioned, even if no SSH session or test traffic is active. Stopping the VM does not stop those charges.

Before deployment, use the pricing calculator for the actual region, currency, account offer and planned duration. Budget for:

- Azure Firewall Standard provisioned time and processed data.
- Bastion Standard baseline/two scale units, any applicable transfer charges, and provisioned time.
- One `Standard_B1s` VM or the chosen replacement, one OS disk, and two Standard public IPv4 addresses.
- Hub/spoke peering traffic, internet egress and diagnostic ingestion/retention.
- Any organization-specific monitoring/security services automatically enabled by policy.

A planning formula is `duration × hourly services + disk/IP charges + processed/transfer GB + log ingestion/retention`; it is **not a quote or a cap**. No fixed numerical price is supplied because the public pricing pages require region/offer selection and this task did not obtain an account quote. [Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/), [Bastion pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/), [Azure calculator](https://azure.microsoft.com/en-us/pricing/calculator/)

Use a short, supervised session and agree a cleanup time before deployment. A cost alert is useful but does not automatically stop resources. There is intentionally no Log Analytics daily cap that could erase test evidence; log volume itself remains billable. Firewall operations can take many minutes. Do not interrupt a long provisioning operation and blindly create a duplicate deployment.

## Setup and static checks

Commands in this README are **instructions for a future authorized operator**, not actions executed during drafting.

```bash
cd lab  # From the scenario package root
cp terraform.tfvars.example terraform.tfvars
# Edit subscription_id, region, approved image version and owner locally.
export TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/your-approved-key.pub")"

# No Azure API calls are needed for these local checks:
./scripts/check-local.sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/policy_modes.tftest.hcl
```

`init -backend=false` avoids backend initialization, but may still download the provider and contact its registry. It is **not automatically offline**. For a genuinely offline run, use an already approved populated provider mirror, for example `terraform init -backend=false -plugin-dir=/approved/provider-mirror`. This draft has **no generated provider lock file**, and the example image version is **`latest`**, so it is not yet a reproducibly locked deployment. Resolve/pin a concrete image version and successfully initialize the exact provider before deployment. Do not invent a lock file. Retain/review the genuine `.terraform.lock.hcl` generated by successful initialization; do not commit credentials, state, plans, or local `.tfvars`.

The tests use a mock AzureRM provider and **plan-only** runs. They check selection of exactly one collection type, private subnet, DNS proxy, peering flags, SSH authentication and invalid inputs. Do not remove `mock_provider` or turn these into live infrastructure tests without a separate approval. Source checks and five guest-harness tests use synthetic local tools and do not send traffic. They cannot replace Terraform validation or an Azure test. [Terraform mocks](https://developer.hashicorp.com/terraform/language/tests/mocking)

## Deployment, only after explicit authorization

Authenticate using the organization's approved method and verify the active subscription. No secret needs to be written to HCL. Then prepare and review a plan:

```bash
terraform plan -out=lab.tfplan
terraform show -no-color lab.tfplan
```

Check: correct subscription/region, only dedicated lab resources, no modifications to existing shared resources, no VM public IP, only two named service public IPs, computed firewall DNS/route next hop, workload private-subnet setting, intended policy mode, and acceptable costs. Check the provider pin and lock-file provenance. This directory uses local state by default; use an approved encrypted/locked backend for team workflows through a separately reviewed configuration.

**Stop here unless deployment and costs are approved.** An authorized operator can then run:

```bash
terraform apply lab.tfplan
terraform output
```

A successful apply means Azure accepted resource provisioning, not that end-to-end egress passed. Changing `policy_mode`, allowed names, or the script changes VM custom-data and may require VM replacement. Review any such plan; do not treat scenario switching as a harmless runtime toggle. Never copy the mocked test key into real `.tfvars`.

## Remote access without weakening the egress test

Bastion Standard provides the management path:

`operator → Bastion public HTTPS → private hub/spoke peering → VM TCP22`

Only `10.10.1.0/26 → 10.20.1.4:22` is allowed inbound on the workload NSG. SSH responses are stateful and use the more-specific hub peering route. Bastion has its own required NSG rules and Internet/control-plane access; those rules are not workload egress permissions. No default UDR is placed on `AzureBastionSubnet`. [Bastion NSG requirements](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg)

On your **local workstation**, not Cloud Shell:

```bash
RG=$(terraform output -raw resource_group_name)
VM_ID=$(terraform output -raw vm_id)
BASTION=$(terraform output -raw bastion_name)
USER_NAME=$(terraform output -raw admin_username)

az network bastion ssh --resource-group "$RG" --name "$BASTION" \
  --target-resource-id "$VM_ID" --auth-type ssh-key \
  --username "$USER_NAME" --ssh-key "$HOME/.ssh/your-approved-key"
```

Verify the SSH host key through your approved process. Do not turn off host-key checking, upload your private key into the VM, or add public SSH to fix a connection issue. The Azure portal Bastion session is an alternative authorized interface, but the local native client keeps the private key on the workstation. Native client/tunneling requires Standard or higher. [Native client setup](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)

Azure Run Command is **not** the default workaround. It requires outbound TCP443 to Azure public endpoints to return results, and a broad `AzureCloud` network Allow could bypass hostname restrictions for many destinations. Lack of Run Command output is not proof the guest script did not run. [Run Command dependencies](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)

## Demonstration and expected evidence

### 1. Record control-plane configuration

On the management workstation:

```bash
./scripts/collect-control-plane.sh
```

Expect both peerings `Connected`; a running VM with private NIC `10.20.1.4`; the workload subnet's route table/NSG associations; `defaultOutboundAccess: false`; and no VM public-IP/NAT-gateway association. Retain NIC **effective** routes and effective NSGs, not just their configured resource lists. A configured route is not proof it applies to that VM.

The active default route should be `0.0.0.0/0 → VirtualAppliance <actual F>`. More-specific local/hub routes remain. `ip route` inside Linux may still show Azure's subnet gateway, not the firewall. Azure's fabric enforces the UDR; do not rewrite the guest gateway.

### 2. Run the guest harness

In the Bastion SSH session, after cloud-init finishes:

```bash
cloud-init status --wait
cat /etc/egress-demo.json
command -v curl python3 getent ip
/usr/local/bin/egress-demo
```

The script refuses to run if the expected VM private IP is absent. It records UTC timestamps, resolver settings, IPv4 DNS answers and individual curl traces, remote/local ports, headers and exit codes. It starts curl with `-q` to ignore `.curlrc`, then makes fresh TCP connections with IPv4/HTTP1.1, no explicit proxy, no automatic redirects and normal certificate verification. It does not run package installation or claim that any test passed merely from a curl exit code.

If you changed the allowlist, select the approved host explicitly, e.g. `PRIMARY_HOST=your-approved.example /usr/local/bin/egress-demo`; set `ECHO_HOST` to an approved plain-text IPv4 echo service or omit it from the allowlist and use your server logs. `UNLISTED_HOST` must not be in the allowlist. The default unlisted-host request is an observation, not a reliable deny assertion in network mode.

| Case | Expected baseline observation | Required corroboration |
|---|---|---|
| DNS via actual F | Allowed and unlisted public names can resolve | Guest resolver settings and `AZFWDnsQuery` rows; optional `dig` UDP/TCP tests |
| Allowed HTTPS | Valid TLS and an origin response, which may be a redirect or non-2xx | Matching network Allow for actual destination IP in network mode, or application Allow/FQDN in application mode |
| `https://api.ipify.org` | Plain-text body equals actual `firewall_public_ip` | Compare to firewall public-IP resource, not Bastion IP; this endpoint must be approved/allowed |
| `http://www.microsoft.com` | No origin HTTP response | Firewall Deny for the VM's destination TCP80; workload NSG permits TCP80 specifically to expose the firewall decision |
| `https://www.bing.com` in network mode | Conditional: can be denied **or allowed if it shares an allowed IP** | Compare current DNS/IP sets and matching decision; a successful shared-IP connection is not a network-rule malfunction |
| Same unlisted host in application mode | No origin response through a matching Allow | Default-deny evidence; verify there are no network collections, inherited allows or proxy bypasses |
| DNS UDP/TCP directly to `168.63.129.16`, only when `dig` exists | Both direct queries are expected to fail because of the workload NSG, not the firewall | Record both actual outcomes/exit codes plus effective `AzurePlatformDNS` policy; a timeout alone does not identify the cause. If `dig` is missing, both are **NOT RUN** and bypass prevention is unverified. |
| External UDP443/TCP22 | Configuration predicts NSG denial | **Not implemented by the supplied harness; NOT RUN.** The effective NSG can establish configured intent, not an observed packet result. No firewall-deny claim is made. |

If `dig` is absent, the harness emits `DNS_BYPASS_VERDICT=NOT_RUN`. Resolver settings and ordinary `getent` lookups can still show the configured resolver and name resolution, but cannot establish that direct DNS bypass is blocked. With `dig`, the harness reports `NEEDS_REVIEW`, not a pass; preserve positive proxy answers and both direct-probe outcomes, then correlate effective NSG rules. Do not install tools through newly broadened egress automatically.

DNS success never authorizes HTTPS. A failed curl can mean DNS, TLS, origin, routing, NSG, or firewall trouble; it becomes a firewall-deny result only with corroboration. A TCP handshake or public ICMP ping is not an end-to-end HTTPS acceptance test.

### 3. Optional next-hop diagnostic

Copy an actual public IPv4 returned by the VM's DNS lookup, then on the management workstation, using an existing authorized Network Watcher:

```bash
TEST_IP='<actual public IPv4 observed inside the VM>'
az network watcher show-next-hop -g "$RG" --vm vm-egress --nic nic-egress \
  --source-ip 10.20.1.4 --dest-ip "$TEST_IP" -o json
```

Expected: `VirtualAppliance` and actual F. This tests route selection, not permission or delivery. If the prerequisite is missing, mark **not run** rather than provisioning extra infrastructure. [Next-hop diagnostic](https://learn.microsoft.com/en-us/azure/network-watcher/next-hop-overview)

### 4. Query firewall decisions and DNS

The diagnostic setting enables `AZFWNetworkRule`, `AZFWApplicationRule`, `AZFWDnsQuery` and `AZFWThreatIntel` into resource-specific tables. It does not enable every expensive trace/aggregation category. Table creation and ingestion can lag; initial activation can take up to 30 minutes. Empty results are initially **inconclusive**. [Firewall monitoring](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall), [Supported categories](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-network-azurefirewalls-logs)

Replace `FIREWALL_RESOURCE_ID` in each query with `terraform output -raw firewall_id`, then run the query in the `law-egress` Logs UI. Or use a previously installed/approved `log-analytics` Azure CLI extension:

```bash
WORKSPACE=$(terraform output -raw workspace_customer_id)
FW_ID=$(terraform output -raw firewall_id)
mkdir -p evidence
sed "s|FIREWALL_RESOURCE_ID|$FW_ID|g" queries/decisions.kql > evidence/decisions.kql
az monitor log-analytics query --workspace "$WORKSPACE" \
  --analytics-query "$(cat evidence/decisions.kql)" -o json > evidence/decisions.json
```

Use `queries/network.kql` for network matches, `queries/application.kql` for the separate application scenario, and `queries/dns.kql` for DNS. Correlate UTC time, VM source IP, client source port, actual destination IP/port or FQDN, rule collection and decision. A denied flow might appear in a different decision table than an allowed one, so use the combined query when needed. Network logs need not expose the final public translated source port. `AZFWNatRule` records DNAT rule matches; it is not an outbound-SNAT proof table.

### 5. Export a small evidence bundle

Save control-plane JSON, the guest session directory and relevant query results. Mark each case **passed**, **failed**, **inconclusive** or **not run** in [RESULTS.template.md](RESULTS.template.md). Do not publish subscription/tenant identifiers, topology, SSH details or full response bodies without review. Do not attach Terraform state or a binary plan as a public evidence artifact.

For file transfer, leave a Bastion tunnel running in a separate local terminal:

```bash
az network bastion tunnel --resource-group "$RG" --name "$BASTION" \
  --target-resource-id "$VM_ID" --resource-port 22 --port 50022
# Another terminal, using the same expected host-key verification:
scp -P 50022 -i "$HOME/.ssh/your-approved-key" -r \
  "$USER_NAME@127.0.0.1:/home/$USER_NAME/egress-evidence-<actual-timestamp>" ./evidence/
```

The native `az network bastion ssh` command itself does not transfer files. The tunnel method requires a local client, not Cloud Shell. [Bastion native client and file transfer](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)

## Troubleshooting order

1. **Cannot SSH:** verify Bastion provisioning, both peerings, all required Bastion NSG rules, workload source `10.10.1.0/26` to TCP22, user/key and host identity. Do not add a workload public IP or a firewall DNAT workaround.
2. **VM still boots or script absent:** inspect boot diagnostics and cloud-init status. Cloud-init failure is not firewall failure. No script is supposed to run automatically.
3. **DNS fails:** check guest DHCP resolver, no NIC override, DNS proxy enabled in the attached policy, peering, and UDP/TCP53 to F. Use the actual computed address. After DNS setting changes, renew/restart appropriately and verify the live resolver.
4. **No firewall rows:** check route/subnet associations, more-specific routes, workload NSG and diagnostics/ingestion delay. A missing log is not permission evidence.
5. **Allow log but application failure:** inspect TLS certificate, guest clock, destination health, DNS/IP changes and redirect target. Do not follow a redirect by silently adding new domains.
6. **Unlisted host works:** in network mode, compare resolved destination IPs first. In application mode, inspect actual rule collections, proxy settings, actual egress IP and new versus existing connections. Network rules terminate processing before application rules.
7. **Public-IP mismatch:** first distinguish firewall IP from Bastion IP. Then check for other routes/NAT/public IPs/proxies or endpoint errors. A mismatch must not be relabeled a pass.
8. **Provisioning denied:** record the actual Azure policy/quota/capacity error. Do not disable policy, choose a different subscription, or create a replacement stack without approval.

## Security and scope caveats

- This is a short-lived teaching environment, not a production baseline. No multi-region recovery, zone-specific resilience proof, capacity/SNAT load test, production patching design or vulnerability assessment is included.
- The default route is not universal inspection. Local/spoke and hub peering routes are more specific; Azure platform traffic has special behavior. The workload NSG deliberately denies new ordinary private east-west traffic except DNS and Bastion SSH, but that is a separate control.
- Network FQDN rules permit IPs, including shared hosting exposure and any protocol carried over permitted TCP443. Application mode is better for HTTPS hostname intent but still lacks TLS decryption and URL-path/content inspection. Neither mode proves complete data-exfiltration protection.
- There is no IPv6/QUIC demonstration, no forced tunneling, and no NAT Gateway. Adding NAT Gateway to the firewall subnet changes the external source IP and requires new evidence/diagrams.
- `AzurePlatformDNS` is blocked only on the workload subnet to avoid bypassing the DNS proxy. Do not indiscriminately block all of `168.63.129.16`: other platform functions depend on it. DNS-over-HTTPS inside an otherwise permitted connection is not addressed by blocking port 53.
- Threat intelligence is **Alert**, not Deny, to keep teaching decisions attributable to the named rules. This is a conscious lab tradeoff, not a recommendation to weaken production policy.
- OS/package updates and most monitoring-agent/extension endpoints are not allowlisted. Do not operate the VM as a maintained production host in this state. Azure Run Command's dependencies are intentionally not broadly allowed.
- Bastion is public HTTPS with Azure authorization and SSH authentication; it adds management exposure and cost. Its full service NSG rules are separate from the VM's narrow inbound rule. Review source restrictions and organization controls before production use.
- Terraform state can contain provider-returned workspace shared keys even though this template never outputs them and local authentication is disabled. Protect all state and plans as sensitive. Managed boot diagnostics and logs also contain operational details. Local state is not a team-safe encrypted backend.

## Cleanup after an authorized deployment

Save the evidence first. Confirm that the state, subscription and resource group belong only to this disposable lab. Preserve any resources that were added/shared later. A resource-group deletion guard refuses deleting a group containing resources Terraform did not remove; do not turn that guard off as a shortcut.

Review a destroy plan:

```bash
RG=$(terraform output -raw resource_group_name)
terraform plan -destroy -out=destroy.tfplan
terraform show -no-color destroy.tfplan
```

**Only after deletion approval**, an authorized operator can run:

```bash
terraform apply destroy.tfplan
terraform state list
az group exists --name "$RG"
```

Expect an empty state and `false` for the dedicated group after deletion completes. If deletion fails, preserve state and inspect the error/remaining resources before retrying. Do not delete the state file to conceal a failed destroy. Check the Azure portal/resource inventory for orphaned firewall, Bastion, VM/disks, public IPs, policy and logging resources; billing views can lag. Workspace soft-delete behavior is not an instruction to purge logs permanently. Stopping/deallocating only the VM is not complete cleanup, and firewall deallocation can change its private IP on later allocation. [Firewall lifecycle FAQ](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq)

## File index and references

- `versions.tf`, `variables.tf`, `main.tf`, `management.tf`, `diagnostics.tf`, `outputs.tf`: independent Terraform root module.
- `terraform.tfvars.example`: safe placeholders; not ready for deployment unchanged.
- `scripts/guest-tests.sh`: guest observations, installed but not auto-run.
- `scripts/collect-control-plane.sh`: authenticated read-only configuration evidence.
- `scripts/check-local.sh`, `tests/`: local source checks and optional provider-mocked plan tests.
- `queries/`: resource-specific KQL.
- `RESULTS.template.md`, `validation/STATUS.md`: separate expected/observed outcomes and exact drafting check scope.
- [SOURCES.md](SOURCES.md): official source links and version-review limits.
