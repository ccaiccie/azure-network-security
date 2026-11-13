# Scenario 14: Azure Firewall application inspection for a Blob Private Endpoint

**Complete source draft, not a deployed or runtime-validated lab.** This builds an owned Blob Private Endpoint, DNS, Standard Azure Firewall application policy, private administration and separate seed/reader identities. It includes both unauthenticated TLS/service reachability and a separately authorized fixed-object upload/read workflow. A403 is **not** successful Blob access, and a200/content match is **not by itself** proof of the inspected path. See [the full guide](../azure-14-private-endpoint-inspection-guide.md), [runtime worksheet](RESULTS.template.md), [validation status](validation/STATUS.md) and [sources](SOURCES.md).

No Azure authentication, identity/RBAC creation, token acquisition, upload/read, deployment, secret generation or repository change was performed in preparing this draft. Provider and actual runtime behavior remain unvalidated. Future persistent access and data changes need explicit operator authorization; a boolean or script flag is an attestation, not permission obtained automatically.

[Scenario overview](../README.md) · [Diagram index](../diagrams/README.md) · [Package checks](../validation/PACKAGE-CHECKS.md)

Run future operator commands from lab/ within this package. Opening these files executes nothing.

## 1. Topology and exact resources

Default dedicated RG: `inspection-pe`. Required region has no default. Four owned VNets:

| Role | Address/resources |
|---|---|
| Hub | `hub`10.0.0.0/16, AzureFirewallSubnet10.0.1.0/26; Standard `hub-firewall`, allocated F, own Standard public IP |
| Clients | `client`10.10.0.0/16, workload10.10.1.0/24; reader A10.10.1.10 and separate seed W10.10.1.11 |
| Endpoint | `endpoint`10.30.0.0/16, dedicated private-endpoints10.30.1.0/24; `blob-pe`, static E10.30.1.7, managed `blob-pe-nic` |
| Administration | `management`10.40.0.0/16, AzureBastionSubnet10.40.2.0/26, Standard `management-bastion` |

Both clients have no public IP, no forwarding and no implicit default outbound. The two VM system-assigned identities are distinct. No writer identity is attached to the reader. One new globally unique StorageV2 account is required, with private container `lab-data` and fixed object `proof.txt`. No existing/shared storage or DNS zone is imported.

Eight directed peerings include hub↔client and hub↔endpoint with forwarded traffic, **explicit client↔endpoint direct peering** as a real competing route, and management↔client without forwarded/gateway transit. All peerings disable gateway transit/remote gateways. Management has no inspection UDR and reaches both VMs directly. There is no claim of transitive hub peering, VPN, vWAN, ExpressRoute or custom NVA.

Client route table `client-pe-inspection` has E/32→VirtualAppliance F and0/0→None, propagation disabled. Only the client subnet receives this table. Never copy E/32→F onto FirewallSubnet, which would recurse. F is an actual allocated output, not assumed .4; the PE address is explicitly configured and must still be observed in an **Approved** connection to the correct owned account/blob subresource. An allocated PE IP can exist even if approval is rejected.

## 2. PE policy, routing and proxy symmetry

Baseline `pe_network_policies="Enabled"` enables both routing and NSG policies on the **PE-hosting subnet**. This is not the separate Private Link Service policy. `RouteTableEnabled` enables routing only; `NetworkSecurityGroupEnabled` NSGs only; `Disabled` neither. The setting affects every PE on that subnet, which is why this lab owns a dedicated subnet.

The PE belongs to address block10.30/16. An enclosing UDR prefix length N≥16, up to/32, can qualify under the platform's PE-policy override mechanism.0/0 or10/8 cannot. An eligible10.30/16 UDR is not automatically wrong just because the endpoint advertises/32. This is a special PE-policy rule, not ordinary longest-prefix logic claiming every/16 beats every/32. The module uses explicit E/32 for clarity. Verify the client effective route against the real direct peering/InterfaceEndpoint competitor; a timeout cannot prove selected route because the PE NSG also blocks direct A/W sources.

Policy `pe-policy`, group `blob-rules` priority200, has only exact HTTPS application collections:
- `reader-blob` priority100, rule `reader-to-owned-blob`, A/32→ordinary owned Blob FQDN443.
- `seed-blob` priority110, rule `seed-to-owned-blob`, W/32→the same exact FQDN443.

Each collection starts Deny and has its own Allow gate. The Terraform policy-rule schema uses `destination_fqdns`. There is no network443 Allow, DNAT, URL/body filtering, parent policy or Premium TLS decryption. Threat intelligence is Alert. Standard uses HTTPS/SNI application filtering; the client validates the real service certificate. Do not draw a customer CA, decrypted HTTP legs or HTTP-header visibility in this Firewall.

Application proxying creates an onward S:s→E443 connection even though E is private. S is an observed Firewall-side address in its subnet, not necessarily F, and s need not equal A's/W's source port. Service replies return on that S-side connection, then Firewall state returns data to the original client socket. No new service→client connection or PE guest route is invented. The service's logged caller address is an observation, not a promised view of any one internal tuple. A network-rule substitution would have different SNAT behavior and is not implemented. Microsoft's customer-NVA `disableSnatOnPL` option remains reference-only, not a managed-Firewall tag or a lab switch.

## 3. DNS and independent NSG controls

Use `ACCOUNT.blob.core.windows.net`, not an IP URL or privatelink alias. Its CNAME chain leads to the owned `privatelink.blob.core.windows.net` zone; the PE zone group supplies the A record. Only hub is linked, allowing Firewall's default Azure DNS upstream to resolve privately. The link uses `resolution_policy="Default"`, not NXDOMAIN Internet fallback. Both client NICs use F as DNS server. DNS proxy is enabled in the Firewall policy. The helper and topology are IPv4-only: A-answer validation does not test AAAA/IPv6 behavior.

Client NSGs, one per VM:
-100 outbound ownIP/32→E/32 TCP443, separately gated for reader and seed.
-110 inbound SSH from management10.40.2/26 only.
-200UDP and201TCP outbound DNS53 only to F, controlled by `dns_enabled`.
-210 outbound AzurePlatformDNS Deny, plus4000 other inbound/outbound Deny.
-220 `platform-imds`: **always Allow** TCP80 to host-local AzurePlatformIMDS. Cloud-init needs IMDS network/pre-provisioning metadata at boot; blocking it until roles exist can prevent provisioning. IMDS is not general Internet egress. Any process on a VM can request its available identity's token; the separate VMs, approved identity creation and container RBAC are the data-access boundaries. No token or Blob operation is run by cloud-init or automatically by a helper.

PE subnet NSG `endpoint-nsg` permits only FirewallSubnet10.0.1.0/26→E443 at priority100 when `pe_ingress_enabled`; priority4000 denies other inbound. Source ports are wildcard, consistent with PE NSG limits. No made-up PE outbound/service-initiated test is included. Opening the proxy envelope does not open the reader/seed envelope or application collection.

As reviewed4November2026, Microsoft documents unavailable PE NSG support in West India, Australia Central2, South Africa West, Brazil Southeast, and government/China regions. This module targets Azure public cloud and requires a supported region. Recheck current limitations and Firewall capacity; the current capacity table blocks new Standard Firewall in East US. Never silently choose another region.

## 4. Prerequisites, access and cost

Provide an approved subscription, new RG/account name, region/quota/budget, existing **public** SSH key and concrete same-subscription Compute Gallery image version. The approved image must already have Python3/SSL, the Ubuntu public CA bundle `/etc/ssl/certs/ca-certificates.crt`, current time, iproute2, dig, cloud-init and SSH. No package install, image build, key generation or mutable latest image is supplied. DNS is closed initially; package/bootstrap Internet access is not a workaround.

Terraform>=1.9,<2 and AzureRM5.12.0 are pinned. Pinned official Storage Account, PE, DNS-link and container source were reviewed; the container implementation uses Resource Manager create/read rather than uploading a blob. This is source review, not loaded schema/provider execution. The pinned subnet document fetch was unavailable; current four-value enum docs informed it. No lock file is fabricated. Review/create a provider lock in the authorized environment and verify `fmt`, schema and mock plans before any deployment. No provider was installed here.

Creating VM system identities and container role assignments expands persistent access and requires explicit action-time approval. `identity_access_authorized` records that approved intent; deployment also requires the image attestation. Actual permission to create resources/assign roles must exist at the approved scopes. No client secret, account key or SAS is used. Role grants are independently false:
- reader: Storage Blob Data Reader at the **owned container ARM ID**.
- seed: Storage Blob Data Contributor at that same container, only for seeding, then revoked. This role includes more than one-object write/delete, so the container is dedicated and the helper itself only creates the fixed synthetic object. No account/RG/subscription-wide grant is added.

Role creation/propagation/revocation is asynchronous. Do not claim revocation instantly invalidates every issued token. Close seed application and443 paths before removing the writer role, and keep them closed. The reader VM must never inherit or receive the writer identity. Review actual role scope/principal and any competing broader grants.

Storage disables public network access, Shared Key authorization, anonymous/nested-public access, local users, SFTP/NFS and HNS; HTTPS/TLS1.2 is required. Network rules default Deny without trusted-service bypass. The private container is created through ARM; **Terraform does not upload the proof blob**. Do not temporarily enable public access or keys to fix provisioning. Diagnose provider/runtime prerequisites instead.

Terraform state/plan may contain Storage account keys and Log Analytics shared keys exported by the provider even though those authentication paths are disabled. State is not identifiers-only. Protect plans/state/cache/CLI files and all evidence. `--query` limits retained stdout client-side, not the full response received; metadata, tags and errors may be sensitive. Enter no secrets in tags. The helper never serializes bearer tokens, Authorization headers or raw response bodies; Python cannot guarantee erasure from process memory. Avoid debug tracing/core dumps and never paste a token into a shell command or document.

Costs include continuous Standard Firewall, Standard Bastion, two VMs/disks, two public IPs, Private Endpoint/data processing, Storage operations/retention, private DNS, peering and logs. Closing gates does not stop charges. Estimate the chosen region/subscription with the Azure pricing calculator before approval; no live quote is included. Blob/container soft-delete retention is one day, and applicable service retention/recovery can outlast a logical delete.

## 5. Local checks and deployment staging

All16 booleans in `terraform.tfvars.example` default false: deployment/image/access approval, PE/DNS/routes attestations, DNS/PE/client/seed envelopes, two application Allows, two role grants and two isolated-experiment attestations. Baseline policy Enabled and `install_pe_host_route=true` are true/active defaults. `deploy_lab=false` after a deployment means destruction, not pause.

Run only source/mock checks locally:
```bash
bash scripts/check-local.sh
```
In a separately approved preparation environment, future provider checks are:
```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test -filter=tests/baseline.tftest.hcl
```
These were NOT RUN here. Initialization can download provider software; review sources/lock and permissions first. The supplied tests are mock-provider **plan-only** cases, not live provider tests. A real plan and any apply/destroy need separate review/authorization; no apply/destroy command is included.

First deploy only the approved substrate: deployment/image/access gates true, every flow/role gate false. This creates distinct VM identities but no Blob data grants. Cloud-init writes only public configuration/helpers; it does not request tokens, seed content or run a network test. Verify actual resources, helper files, VM readiness and private management before advancing. Account/PE/F changes can alter custom-data or replace resources/VMs; close all requests/gates and review the full plan before changes.

## 6. Administration and control-plane evidence

On the approved operator terminal, require explicit subscription and strict identity guard:
```bash
export SUBSCRIPTION_ID="REPLACE_WITH_APPROVED_UUID"
source scripts/common.sh
load_context
az extension show --name bastion --query name -o tsv
```
The helper disables dynamic extension installation. Install missing approved tooling through the normal authorized workflow, not as a hidden read side effect. `load_context` validates every core resource ID, exact reader/seed VM/NIC map, VNet map, Blob destination, distinct identity UUIDs and conditional container-scoped role ID map before reads. An empty role map is required while both grants are false; missing/null is not interpreted as healthy.

Use the existing approved private key locally through native Bastion, never paste/upload it into this lab:
```bash
: "${EXISTING_SSH_KEY_PATH:?Set approved local private-key file path}"
az network bastion ssh --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" --name "$(read_output bastion_name)" \
  --target-resource-id "$(read_map_output vm_ids reader)" \
  --auth-type ssh-key --username labadmin --ssh-key "$EXISTING_SSH_KEY_PATH"
```
Use `seed` for the separate upload VM and the configured username if changed. Verify host keys normally. This is private VM access through public Standard Bastion, not a claim of a private-only Bastion deployment.

Collect a fresh private snapshot:
```bash
RUN=$(mktemp -d -t pe-review-XXXXXXXX)
bash scripts/collect-control-plane.sh "$RUN/control"
```
The final OUT must be nonexistent; existing directories/symlinks are refused. Default output is unique timestamp/PID. It records start/end UTC, each JSON/stderr/exit, private-handling notice and incomplete-evidence requirements. Every Azure read is subscription-scoped. No listKeys/SAS/IMDS/token/Blob operation is included. VM identity reads can involve a full response before client-side projection, so keep raw errors and CLI state private.

Review actual PE Approved state and exact storage ID/blob subresource, E allocation, zone group/A record/link, policy flags, NSGs, A and W effective routes, direct peering competitor, F's onward endpoint reachability and management paths. Do not call a PE NIC effective-route/security command or invent inbound PE NSG flow logs: those views are not supported. Empty `customDnsConfigs` can be normal with a valid zone group; an allocated E alone is not readiness.

Set `pe_ready=true` only after those control-plane checks. Enable `dns_enabled=true`, then run on each VM:
```bash
pe-ready
```
It verifies exact source NIC, OS resolution only to E, bounded dig queries to F for ordinary and privatelink names with A/TTL evidence, and the approved CA bundle. It acquires no token and performs no TLS/Blob request. Save stdout in a fresh private file. It proves neither actual Firewall application filtering nor a TLS handshake. Only after consistent DNS and actual route evidence set `dns_verified` and `routes_verified` true.

## 7. Controlled reachability, seed and read sequence

For each exposure update, review the exact plan and obtain the needed authorization. Preserve E/32, Enabled policies and DNS throughout live testing.

1. Open PE ingress, then only reader443 envelope, keeping both application collections Deny and both role grants false. A fresh noauth case should fail at the named reader application rule; require matching AZFWApplicationRule tuple/time/FQDN/action. A failed TCP/TLS request has no HTTP client-request-id at the service.
2. Open only reader application Allow. On A:
```bash
RUN=$(mktemp -d -t pe-cases-XXXXXXXX)
pe-probe noauth --out "$RUN/noauth"
```
Strict TLS to E with ordinary hostname/SNI and service status metadata can establish reachability when combined with routes/logs.403 is not authorized data access, and403 alone can also occur on a public path. The helper always leaves private_path_proven/firewall_inspection_proven false for operator evidence review. Immediately restore `allow_client_blob=false` while the reader443 envelope is still available, run a fresh `pe-probe noauth` case into a new evidence directory, and require matching named `reader-to-owned-blob` Deny evidence. Then set `client_paths_enabled=false` and verify reader NIC closure before reviewing the first reachability result or proceeding to any token-bearing operation. PE ingress may remain available for the separately approved seed phase.
3. Separately authorize the seed identity's **container-scoped Contributor grant**, opening only seed443/seed application Allow and PE ingress after role propagation. On W, the fixed operation is51 public synthetic bytes at `/lab-data/proof.txt`:
```bash
RUN=$(mktemp -d -t pe-seed-XXXXXXXX)
pe-probe seed --confirm-token-use --confirm-data-operation --out "$RUN/create"
```
The exact content is in fixtures/proof.txt; SHA256 is `003da15a8a946410c90f1216eb109b19e40ba6b307fee105d277cb43cc07e8e0`. PUT BlockBlob uses `If-None-Match:*`, RFC1123 x-ms-date and a unique x-ms-client-request-id. It cannot overwrite an existing object or upload an arbitrary file.201 with an empty response is CREATE_ACCEPTED, still requiring subsequent independent read/hash and service evidence.409/412, interruption or timeout is not permission to retry/delete: inspect whether creation occurred, retain evidence and stop.
4. Finish seed requests, restore `allow_seed_blob=false` and `seed_paths_enabled=false`, then revoke `grant_seed_role` in the same or a subsequent approved closed update. **Never set grant_seed_role=false while allow_seed_blob=true**, because validation correctly rejects that inconsistent stage. Verify current seed Deny/NSG closure and role removal; token/revocation caching is not instantaneous. IMDS metadata remains available for platform operation, but no writer role or open Blob path should remain.
5. Separately authorize reader's container Reader role. After propagation, open reader443/application Allow. On A:
```bash
RUN=$(mktemp -d -t pe-reader-XXXXXXXX)
pe-probe read --confirm-token-use --out "$RUN/read"
pe-probe noauth --out "$RUN/auth-negative"
```
Only authenticated200 plus **exact51-byte content** makes `authorized_blob_read_proven=true`; the fixed SHA is checked as evidence. The unauthenticated request under the same network Allow is a separate auth-negative, not a Firewall Deny. Check actual service status/authentication, not merely a helper exit code.
6. Restore reader application Deny and run a **fresh noauth** case while DNS/PE/client NSGs remain healthy. Require named `reader-to-owned-blob` Deny. Then close reader443 and PE ingress, stop all outstanding requests and verify isolation before route experiments or cleanup.

All probes use one bound client socket, only DNS-validated E, ordinary hostname TLS validation, fixed image CA bundle,5second socket timeout and30second whole-operation alarm. There are no redirects, proxies, retries or reconnects. Authorized modes obtain an IMDS token only for `https://storage.azure.com/` using Metadata:true and the VM's primary source, keep it in memory, and never serialize its response. Echoed token values in permitted response headers/body are suppressed. Only a narrow validated response-header allowlist and body length/hash are retained, not Date/raw bodies/Authorization. Fake TLS tests do not validate real certificates, roots, expiry, service trust or Azure tokens.

Each new private evidence directory contains runtime-config.json, result.json and attempt.json once the source socket is bound. Attempted local/destination tuples and UTC survive connect failures. Errors record class/stage only; raw exception text may be sensitive. Interrupted operations can have uncertain service-side outcomes, especially PUT. A successful helper invocation can still be NEEDS_REVIEW; noauth/auth errors must be interpreted with full evidence.

## 8. Evidence, isolated route experiments and teardown

Use queries/application-rule.kql for A/W tuple, UTC, ordinary FQDN, collection/rule/action and IsTlsInspected. Standard non-decrypted HTTPS has no promised TargetUrl, request body or x-ms-client-request-id in Firewall logs. Use queries/blob-service.kql for the owned account and the helper case UUID in StorageBlobLogs, with status/authentication/requester and observed caller address. Do not force a direct join on an HTTP header the Firewall cannot see; correlate the two evidence chains with client tuple/time. Do not export AuthenticationHash, token details or arbitrary URI/query strings.

Implemented **configuration-only** variants are `install_pe_host_route=false` and PE policy enums Disabled/RouteTableEnabled/NetworkSecurityGroupEnabled. Nonbaseline values require deployment, `route_experiment_acknowledged=true`, `isolation_verified=true`, and every PE/client/seed/application flow gate false. DNS may remain available for observations. These guard inputs cannot themselves prove old sessions have ended. First stop all helper processes, close both application collections and both client443/PE envelopes, verify current isolation, then review the route/policy change. Collect route/config evidence only; do not send a live bypass request. Restore Enabled and E/32, recheck PE/DNS/routes, clear stale readiness attestations as appropriate and repeat baseline checks before reopening. Disabled PE NSG policy removes that barrier; client closure is essential.

Cleanup sequence:
1. Finish or stop only the exact owned helper processes, preserve completed/uncertain outcomes and ensure no request remains. There is no daemon/listener fixture to stop.
2. Restore both application Deny actions, verify fresh named Deny while appropriate transport is still healthy, then close both client443 envelopes and PE ingress. NSG established flows can persist; verify they have ended. Firewall policy updates and service authentication have separate timing.
3. Remove the seed grant only with seed Allow already false; remove reader grant after reader requests finish. Verify exact lab principal/scope removal, without assuming immediate token invalidation. Keep private administration and route steering until isolation is established.
4. Retain public storage access Disabled and Shared Key/anonymous Disabled throughout. Never delete DNS, disable PE policies or remove E/32 first as a cleanup shortcut. If a failure makes current state uncertain, investigate rather than treating an absent log as closure.
5. Review synthetic-data deletion and one-day soft-delete/service retention implications. Separately authorize destruction of only the new owned account/container/PE/zone/links/roles/VMs/Firewall/Bastion/resources. This source owns no preexisting data, image or shared zone. Do not use cleanup to purge user data or remove unrelated roles. `deploy_lab=false` is destructive, not pause.
6. Verify final resource/role absence and no billable storage/PIP/disk/PE/log leftovers using approved reads; retain private state/evidence only under the authorized retention policy. Actual cleanup was NOT RUN.
