# Scenario 07 source and validation boundaries

Primary references reviewed 2026-11-04. Reading documentation is not an Azure deployment, provider-schema check, FRR configuration parse, Linux/GRE test or failover result.

## Azure service behavior and operations

- [Route Server FAQ](https://learn.microsoft.com/en-us/azure/route-server/route-server-faq): control-plane role, both service instances, ASN/timers, supported deployment and protected local-route constraints. Current capability must not be described using obsolete blanket limitations.
- [Create Route Server](https://learn.microsoft.com/en-us/azure/route-server/quickstart-create-route-server-portal): dedicated service subnet and public management address. This design uses /26, following current service guidance rather than older provider Markdown's /27 text.
- [Virtual network routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview): longest-prefix/type rules and protected route exceptions. Read actual effective-route source/type/next-hop fields rather than imposing a fictional BGP enum.
- [Multi-region architecture](https://learn.microsoft.com/en-us/azure/route-server/multiregion) and [troubleshooting](https://learn.microsoft.com/en-us/azure/route-server/troubleshoot-route-server): disable propagation on NVA substrate to avoid self-routing, maintain control/tunnel underlay and avoid unsupported VirtualNetworkGateway UDRs.
- [VPN/ExpressRoute integration](https://learn.microsoft.com/en-us/azure/route-server/expressroute-vpn-support): branch-to-branch scope and gateway coexistence caveats. This isolated lab sets it false and has no gateway.
- [FRR simulation tutorial](https://learn.microsoft.com/en-us/azure/route-server/peer-route-server-with-virtual-appliance): teaching simulation is distinct from supported production appliances.
- [Azure service-side route maps](https://learn.microsoft.com/en-us/azure/route-server/route-maps-about): separate preview/upgrade/extra-charge capability, not used here. The implemented route maps and own-AS prepend belong to FRR on the NVA, not this Azure preview.
- [Next-hop IP support](https://learn.microsoft.com/en-us/azure/route-server/next-hop-ip): ILB next hop is an available alternative, not this lab.
- [Bastion NSG rules](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg): management service rules remain separate from workload paths.
- [Route Server CLI peering commands](https://learn.microsoft.com/en-us/cli/azure/network/routeserver/peering?view=azure-cli-latest): core read commands for actual learned/advertised routes and peer objects, explicitly subscription-scoped in the collector.
- [Route Server monitoring](https://learn.microsoft.com/en-us/azure/route-server/monitor-route-server): use current metric definitions/dimensions and per-peer/per-instance evidence. Its displayed virtual-hub data-processed metric is not applicable; aggregate status is not packet or session-continuity proof.

## FRR and Linux implementation

- [FRR stable10.4 BGP documentation](https://docs.frrouting.org/en/stable-10.4/bgp.html): no-rib versus disabling zebra, network import-check, exact prefix maps, per-peer maximum-prefix and outbound limit behavior. The image must contain an explicitly approved exact version in this reviewed family; no version is installed here.
- [FRR stable10.4 setup](https://docs.frrouting.org/en/stable-10.4/setup.html): integrated config, daemon selection, vtysh/service loading. Actual image service packaging is a prerequisite.
- [FRR stable10.4 bgp_vty.c](https://raw.githubusercontent.com/FRRouting/frr/stable/10.4/bgpd/bgp_vty.c): enabled-default import-check can be omitted by configuration serialization. The source checker accepts this pinned-family default but explicitly rejects disabling it; bootstrap explicitly sets it on.
- [FRR stable10.4 bgp_route.c](https://raw.githubusercontent.com/FRRouting/frr/stable/10.4/bgpd/bgp_route.c): advertised-route JSON includes advertisedRoutes and totalPrefixCounter. Reconciliation fails closed if those expected observations are missing or nonempty; an offline mock does not establish actual runtime schema.
- [Linux conntrack sysctls](https://docs.kernel.org/networking/nf_conntrack-sysctl.html): strict midstream pickup setting. No synchronized conntrack is implemented.
- [Linux IP sysctls](https://docs.kernel.org/networking/ip-sysctl.html): forwarding changes can reset IPv4 defaults. Helpers set forwarding first and verify their owned hardening values; they do not claim complete OS rollback.
- [cloud-init write_files reference](https://docs.cloud-init.io/en/latest/reference/modules.html#write-files) and [Terraform base64gzip](https://developer.hashicorp.com/terraform/language/functions/base64gzip): compressed controller delivery. Local encoded-size estimates are not the actual Terraform-rendered payload or cloud-init execution.

## Pinned provider and honest gaps

Code pins AzureRM5.12.0 and Terraform>=1.9,<2. The research brief verified the exact provider implementation exports virtual_router_ips, virtual_router_asn and routing_state; Markdown's short attribute list is not evidence those fields do not exist:

- [5.12.0 Route Server resource implementation](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/internal/services/virtualwan/route_server_resource.go)
- [5.12.0 Route Server documentation](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/route_server.html.markdown)
- [5.12.0 BGP connection documentation](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/route_server_bgp_connection.html.markdown)

The lab worker's exact-version web fetches returned cache misses. Successful independent direct reads were official current [Route Server](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route_server.html.markdown) and [BGP connection](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route_server_bgp_connection.html.markdown) documentation. Current main can change. No Terraform executable, HCL parser, provider binary/cache, init, schema validation, actual plan or provider lockfile was available/generated. Do not describe source review or supplied mock plans as pinned-schema execution.

## Costs

Check the [pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/), [Route Server pricing](https://azure.microsoft.com/en-us/pricing/details/route-server/), [Linux VM pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/), [Bastion](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/) and [managed disks](https://azure.microsoft.com/en-us/pricing/details/managed-disks/) for the actual region, SKU, offer, currency and duration. This draft quotes no total or free-lab promise.
