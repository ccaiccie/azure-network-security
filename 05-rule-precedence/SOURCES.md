# Official sources, reviewed 2026-11-04

Documentation review is not provider schema, deployment or packet validation. AzureRM5.12.0 is pinned; no provider was downloaded or initialized. Some version-tagged source URLs could not be fetched; current official main/Registry documentation was used and that limitation remains explicit.

## Azure behavior

- [Firewall rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing): rule types, terminating matches, parent/child and numerical priority, HTTP Host/port and built-in infrastructure processing. DNAT/inheritance/Premium are conceptual here, not implemented tests.
- [Application versus network SNAT](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range): application transparent-proxy SNAT regardless of private destination, unlike default RFC1918 network behavior.
- [DNS proxy](https://learn.microsoft.com/en-us/azure/firewall/dns-settings): explicit proxy and VNet resolver configuration.
- [Private DNS VNet links](https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links): hub resolution link and disabled autoregistration; records shared with the linked VNet.
- [Azure routes](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview): longest-prefix candidates, RFC1918 None and user/peering routing.
- [VNet peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview): forwarding/access and nontransitive topology.
- [NSG behavior](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-group-how-it-works): stateful response handling versus a new reverse connection.
- [Bastion NSG requirements](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg), [native client](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux): separate private management path.
- [Known issues/current capacity](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues): East US Standard new-deployment restriction and current inheritance/DNS caveats. Region is intentionally required, not defaulted.

## Provider schema references

- [AzureRM5 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/5.0.0/docs/guides/5.0-upgrade-guide): removed Private DNS child zone/resource-group arguments replaced by `private_dns_zone_id`.
- [Private DNS A record](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/private_dns_a_record.html.markdown), [VNet link](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/private_dns_zone_virtual_network_link.html.markdown): current ID-based arguments.
- [Firewall policy groups](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy_rule_collection_group.html.markdown): exact application/network types, protocols and priority limits.
- [Firewall policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy.html.markdown): Standard SKU, DNS proxy and TI mode.
- [Pinned AzureRM5.12 Log Analytics workspace](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/log_analytics_workspace.html.markdown): versioned source was fetched and reviewed; primary/secondary shared keys can enter state despite disabled local authentication. This documentation review is not execution of the pinned provider.
- [Terraform tests](https://developer.hashicorp.com/terraform/language/tests), [mock provider](https://developer.hashicorp.com/terraform/language/tests/mocking): supplied plan-only mocks still need Terraform/provider schema; they are NOT RUN.

## Evidence and tooling

- [AZFWNetworkRule](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule): actual source/destination tuples, action and deciding rule.
- [AZFWApplicationRule](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwapplicationrule): FQDN/URL and action; no DestinationIp column. HTTP does not prove TLS inspection.
- [Firewall CLI rule groups](https://learn.microsoft.com/en-us/cli/azure/network/firewall/policy/rule-collection-group): approved extension prerequisite; implicit installation disabled.
- [curl manual](https://curl.se/docs/manpage.html): first-option-q, proxy disabling, bounded fresh requests and User-Agent/header evidence.
- [Python http.server](https://docs.python.org/3/library/http.server.html): standard-library local fixture primitive, not a production web-server claim.
- [Azure calculator](https://azure.microsoft.com/en-us/pricing/calculator/): future region/time/traffic estimate, no price quote in this draft.
