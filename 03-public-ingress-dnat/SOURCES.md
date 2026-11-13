# Official sources and limits

Reviewed 4 November 2026. This independent derivative follows the supplied scenario03 design brief. Source review is not deployed-state, Terraform/provider or Azure validation.

## Provider and Terraform

- [AzureRM changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md): prior series review identified 5.12.0 dated 29 October 2026; exact pin reused.
- [NAT rule collection schema](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy_rule_collection_group.html.markdown): checked singular destination_address, source_addresses, Dnat action and translated port/address. The exact v5.12.0 page could not be fetched; main-branch docs are not a loaded pinned schema.
- [Route table ownership](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route_table.html.markdown): inline routes need explicit empty-list handling for removal. This lab therefore exclusively uses standalone azurerm_route resources, so the last route has a concrete deletion address.
- [Route resource](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/route.html.markdown): standalone route fields and optional next-hop IP checked; pinned provider schema not loaded here.
- [Subnet configuration](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/subnet.html.markdown): explicit default outbound disabled; separate association resources and governance caveats.
- [Firewall](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall.html.markdown), [Policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy.html.markdown), [Linux VM](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/linux_virtual_machine.html.markdown), [Bastion](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/bastion_host.html.markdown): service patterns reused from the earlier independently reviewed labs; no provider validation is implied.
- [Provider-mocked tests](https://developer.hashicorp.com/terraform/language/tests/mocking): all eleven supplied runs remain mocked and plan-only. They have not been executed.

Terraform/OpenTofu are not installed. No init, lock generation, fmt, validate, Terraform test, real plan, apply or destroy occurred. No provider packages were downloaded. The required image is a concrete operator-selected version; `latest` is deliberately rejected.

## Packet behavior and evidence

- [Azure Firewall-only public request walkthrough](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gateway/firewall-application-gateway#azure-firewall-only-design): public DNAT also translates source to an internal instance; return destination is that instance. Frontend and instance addresses are distinct concepts.
- [DNAT policy tutorial](https://learn.microsoft.com/en-us/azure/firewall/tutorial-firewall-dnat-policy), [DNAT rules](https://learn.microsoft.com/en-us/azure/firewall/destination-nat-rules), [Rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing): scoped publication and implicit allow semantics.
- [Route selection](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview), [Peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-peering), [NSG processing](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-group-how-it-works), [NSG state](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview).
- [AZFWNatRule schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnatrule): original tuple plus translated destination; no Action or translated-source field.
- [Resource-specific monitoring](https://learn.microsoft.com/en-us/azure/firewall/monitor-firewall#resource-specific-mode): NAT rows only for matching rules; no unmatched NAT Deny expectation.
- [Bastion required NSGs](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg), [Native SSH](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux), [Run Command egress](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command).
- [CLI configuration/environment variables](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration), [CLI extensions](https://learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-overview), [Firewall policy CLI](https://learn.microsoft.com/en-us/cli/azure/network/firewall/policy/rule-collection-group?view=azure-cli-latest): require preapproved installed extensions; suppress first-use dynamic installation for evidence reads.
- [Forced tunneling](https://learn.microsoft.com/en-us/azure/firewall/forced-tunneling), [Managed capture](https://learn.microsoft.com/en-us/azure/firewall/packet-capture), [Known issues](https://learn.microsoft.com/en-us/azure/firewall/firewall-known-issues): expanded architectures/features have separate constraints and are not configured by this draft.
- [curl reference](https://curl.se/docs/manpage.html#-q): `-q` first suppresses .curlrc.

## Dated capacity blocker

Verified 4 November 2026: [Microsoft current capacity constraints](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues#current-capacity-constraints) lists new Azure Firewall Standard deployments in East US as blocked. The original eastus sample/default was retained, not silently replaced. Region approval and current capacity verification remain prerequisites.

## Costs

[Firewall](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/), [Bastion](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/), [Azure calculator](https://azure.microsoft.com/en-us/pricing/calculator/). No region/account/currency quote or capacity check was made.
