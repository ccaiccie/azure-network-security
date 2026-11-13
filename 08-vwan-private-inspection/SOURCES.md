# Primary sources and review limits

Reviewed 2026-11-04. Links are documentation, not runtime evidence. Current main-branch provider documentation is not a substitute for the exact pinned provider schema. Direct fetches of v5.12.0 virtual_wan, virtual_hub and firewall Markdown returned cache misses in this environment. No provider executable, schema, init, plan or validate was run.

## Routing, Firewall and evidence

- [Routing intent, prerequisites, platform datapath, association/propagation and removal](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies). The lab uses PrivateTraffic only. Avoid competing connection routing configuration; preserve actual before/after snapshots.
- [Hub effective-route views](https://learn.microsoft.com/en-us/azure/virtual-wan/effective-routes-virtual-hub). Record selected entity and actual onward routes; this does not establish a working CLI Firewall type token.
- [vhub CLI and extension](https://learn.microsoft.com/en-us/cli/azure/network/vhub?view=azure-cli-latest). RouteTable is documented. Firewall effective-route resource-type is a free-string candidate in this draft, not validated; no hardcoded singular/plural token is represented as proven.
- [Firewall rule processing and changes](https://learn.microsoft.com/en-us/azure/firewall/rule-processing#rule-changes). Allow-to-Deny updates are documented to drop applicable existing sessions; actual propagation and measurement still required.
- [Default network-rule private SNAT behavior](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range). The narrow RFC1918 test expects source preservation; application-proxy behavior is not used.
- [AZFWNetworkRule table](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwnetworkrule). Rule/action/tuple/time fields used by the supplied KQL template.
- [NSG stateful flow behavior](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview). Rule changes alone do not prove older flows ended.
- [Bastion NSG requirements](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg).
- [Bastion native-client CLI](https://learn.microsoft.com/en-us/cli/azure/network/bastion?view=azure-cli-latest). Existing approved extension and existing operator key required.
- [Firewall known issues and regional capacity](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues). Recheck chosen secured-hub region and relevant product/SKU before provisioning; no capacity reservation or success inferred.
- [Virtual WAN pricing concepts](https://learn.microsoft.com/en-us/azure/virtual-wan/pricing-concepts). Estimate actual region/offer; published example prices are not this lab's quote.

## Provider documentation inspected (current main)

- [virtual_wan](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/virtual_wan.html.markdown)
- [virtual_hub](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/virtual_hub.html.markdown)
- [virtual_hub_connection](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/virtual_hub_connection.html.markdown)
- [virtual_hub_routing_intent](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/virtual_hub_routing_intent.html.markdown)
- [firewall](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall.html.markdown)
- [Pinned Log Analytics workspace documentation](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/log_analytics_workspace.html.markdown). This pinned resource documentation lists exported primary/secondary shared keys, as cited in the companion guide. This is the reason to protect state even with local authentication disabled; no keys were retrieved.

The supplied mock-provider tests are intended to check key resource attributes only after a legitimate local provider initialization. They cannot prove Azure API acceptance, hidden platform changes, actual intent convergence, computed connection drift, effective routes, logging, billing or packet inspection.
