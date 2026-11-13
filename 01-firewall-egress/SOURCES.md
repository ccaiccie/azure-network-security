# Official sources reviewed

Checked 4 November 2026. Links are source references, not proof that this draft was deployed. Registry pages sometimes returned JavaScript shells or could not be fetched; official HashiCorp provider-source documentation was used in those cases. The draft pins AzureRM 5.12.0, listed at the top of the official changelog as released 29 October 2026. Some resource pages were inspected on `main`, which can change; provider-schema validation against the pinned binary remains required and was not performed here.

## Provider and Terraform

- [AzureRM changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md)
- [AzureRM provider configuration at v5.12.0](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/index.html.markdown): explicit subscription and registration controls.
- [AzureRM 5.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/5.0.0/docs/guides/5.0-upgrade-guide): major-version registration behavior.
- [Firewall resource](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall.html.markdown): Standard SKU, public IP and computed private IP.
- [Firewall policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy.html.markdown): policy DNS proxy and threat intelligence.
- [Rule collection group](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy_rule_collection_group.html.markdown): distinct network/application rule fields.
- [Subnet](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/subnet.html.markdown): explicit default-outbound setting and association caveats.
- [Route table](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route_table.html.markdown): BGP propagation flag and next-hop fields.
- [Bastion host](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/bastion_host.html.markdown): Standard tunneling and /26 subnet.
- [Linux VM](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/linux_virtual_machine.html.markdown): key authentication, image, disk and custom-data fields.
- [Diagnostics at v5.12.0](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/monitor_diagnostic_setting.html.markdown): `Dedicated`, `enabled_log` and `enabled_metric`.
- [Log Analytics workspace](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/log_analytics_workspace.html.markdown): retention, local authentication and workspace/customer ID.
- [Terraform provider mocks](https://developer.hashicorp.com/terraform/language/tests/mocking): optional mock-only, plan-only test design.

## Azure behavior and management

- [Network-rule FQDN filtering](https://learn.microsoft.com/en-us/azure/firewall/fqdn-filtering-network-rules)
- [Firewall DNS configuration](https://learn.microsoft.com/en-us/azure/firewall/dns-settings)
- [Firewall rule order](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)
- [SNAT and private ranges](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range)
- [Firewall FAQ](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq)
- [Current limitations](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues)
- [Bastion NSG requirements](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg)
- [Bastion native Linux client](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux)
- [Run Command Linux outbound dependency](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)
- [Next-hop diagnostic](https://learn.microsoft.com/en-us/azure/network-watcher/next-hop-overview)
- [NIC CLI commands](https://learn.microsoft.com/en-us/cli/azure/network/nic?view=azure-cli-latest)
- [Default outbound access](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)

## Logs and costs

- [Monitor Azure Firewall](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall)
- [Supported log categories](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-network-azurefirewalls-logs)
- [Network-rule table](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule)
- [Application-rule table](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwapplicationrule)
- [DNS-query table](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwdnsquery)
- [Azure Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)
- [Azure Bastion pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/)
- [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
