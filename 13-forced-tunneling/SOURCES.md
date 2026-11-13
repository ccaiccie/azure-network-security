# Primary sources and interpretation boundaries

Reviewed 4 November 2026. Product behavior and capacity can change. Sources support the design; none is a deployment/provider/kernel test result.

- [Azure Firewall forced tunneling](https://learn.microsoft.com/en-us/azure/firewall/forced-tunneling): data-path next hop, management NIC, tenant-data-PIP omission, private-instance SNAT and0/0 private-range suppression. This lab uses a peered NVA, not the article's on-premises tunnel example.
- [Firewall Management NIC](https://learn.microsoft.com/en-us/azure/firewall/management-nic): dedicated minimum/26, service-management public IP and service-provided Internet/default propagation behavior. No customer table/NSG is attached in this module.
- [Firewall private SNAT ranges](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range): network-rule SNAT configuration is different from application-proxy behavior. This lab has no application rules.
- [Azure routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview): longest-prefix selection and user routes; the pure Python route model is explanatory only. Actual effective routes remain mandatory.
- [Virtual network traffic routing through NVAs](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview#user-defined-routes): both Azure NIC and guest forwarding are required; guest FIB is not Azure SDN route evidence.
- [Firewall rule processing and changes](https://learn.microsoft.com/en-us/azure/firewall/rule-processing#rule-changes): assess relevant existing sessions when Allow becomes Deny; do not confuse that behavior with NSG flow persistence.
- [Bastion peered VNet support](https://learn.microsoft.com/en-us/azure/bastion/vnet-peering): management is separately peered rather than routed through the perimeter.
- [Bastion NSG requirements](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg): Bastion has its own mandatory service rules, separate from workload egress.
- [Firewall known issues/capacity](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues): on review date, East US new Standard deployment block and other regional/zonal restrictions. Required region input is deliberate.
- [Current official AzureRM Firewall resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/firewall.html.markdown): management configuration, data IP block and replacement caveats.
- [Current official AzureRM Firewall policy](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/firewall_policy.html.markdown): top-level `private_ip_ranges` contract.
- [Pinned5.12 Firewall documentation target](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/firewall.html.markdown): attempted read returned a cache miss. Current main docs are not evidence that the pinned schema has been loaded or verified. No provider binary, schema or lock was available here.
- [AzureRM workspace resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/log_analytics_workspace.html.markdown): exported primary/secondary shared keys mean state is not identifiers-only.
- [Kernel conntrack sysctls](https://docs.kernel.org/networking/nf_conntrack-sysctl.html): tcp_loose=0 avoids loose midstream pickup; retaining conntrack during this bounded failure is not a state-loss simulation.
- [Kernel IPv4 sysctls](https://docs.kernel.org/networking/ip-sysctl.html): changing ip_forward resets IPv4 configuration defaults; the controller sequences forwarding first, then owned settings. It does not claim to restore every kernel setting on an arbitrary appliance.
- [nftables NAT documentation](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)): stateful NAT and inet-family SNAT require suitable kernel/userspace support. Mocking generated text is not kernel syntax validation.
- [AZFWNetworkRule schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule): tuple/action/rule evidence is distinct from perimeter nftables/conntrack and origin socket observations.
- [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/): estimate exact regional/subscription costs before authorization; this source includes no live quote.

Real VPN/Default Site/BGP/ExpressRoute/FastPath prerequisites are described in the full guide, not implemented here. Do not use this simulator's successful-looking source graph as evidence that any hybrid transport has been tested.
