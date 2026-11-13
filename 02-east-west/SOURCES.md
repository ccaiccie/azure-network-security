# Official sources and review limits

Reviewed 4 November 2026. The implementation follows the supplied scenario 02 conceptual guide but is a separate draft, not a modification of the published repository. No subscription configuration or traffic was queried. Source review does not replace provider-schema or deployment verification.

## Provider and Terraform

- [AzureRM official changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md): 5.12.0 listed for 29 October 2026; exact version pin used here.
- [AzureRM provider configuration at v5.12.0](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/index.html.markdown): explicit subscription and disabled automatic registration.
- [Firewall](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall.html.markdown): Standard VNet firewall and computed private IP.
- [Firewall Policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy.html.markdown): DNS proxy/private-range policy properties.
- [Rule collection group](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy_rule_collection_group.html.markdown): source/destination network rules, ports and separate Allow/Deny collections.
- [Subnet](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/subnet.html.markdown): explicit default-outbound flag and atomic-association caveats.
- [Route table](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route_table.html.markdown): BGP flag and VirtualAppliance/None next hops.
- [Linux VM](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/linux_virtual_machine.html.markdown): public-key auth and image/custom-data configuration.
- [Bastion](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/bastion_host.html.markdown): Standard native tunneling and /26 management subnet.
- [Diagnostics v5.12.0](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/monitor_diagnostic_setting.html.markdown): Dedicated resource-specific mode and log/metric blocks.
- [Log Analytics](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/log_analytics_workspace.html.markdown): workspace/customer IDs, local auth and retention.
- [Terraform provider mocking](https://developer.hashicorp.com/terraform/language/tests/mocking): supplied optional tests remain mocked and plan-only.

Registry pages sometimes returned JavaScript shells or fetch failures; official HashiCorp source docs were used instead. Some resource pages were inspected on the changeable main branch. The exact pinned provider schema has **not** been loaded; init/validate/mock tests remain required. No generated provider lock is supplied.

## Azure architecture and behavior

- [Hub-spoke architecture](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke)
- [Private network-rule SNAT defaults](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range): RFC1918/RFC6598 private destinations preserve source by default; application rules differ.
- [Rule processing and state](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)
- [VNet peering settings](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-peering)
- [Route selection](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview)
- [Single-region and inter-subnet inspection](https://learn.microsoft.com/en-us/azure/firewall/firewall-multi-hub-spoke)
- [Firewall FAQ](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq)
- [Default outbound access](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)
- [Stateful NSGs](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Bastion NSGs](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg)
- [Bastion Linux native client](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)
- [Linux Run Command dependency](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)
- [Next-hop diagnosis](https://learn.microsoft.com/en-us/azure/network-watcher/next-hop-overview)
- [Firewall monitoring](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall)
- [Network-rule log schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule)
- [Current firewall limitations](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues)
- [Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)
- [Bastion pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/)

Region/capacity/prices, actual endpoint readiness and actual Azure results remain unverified. The Python fixed-response fixture is original local demo code, not a production service recommendation.
