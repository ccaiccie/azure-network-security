# Sources and version boundaries

Reviewed 2026-11-04. Only primary Microsoft, HashiCorp and Linux kernel documentation supports the design. Source review is not provider schema execution, an image audit or a runtime test.

- [Azure HA ports overview](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-ha-ports-overview): Standard internal LB, All protocol/port0 model, NVA forwarding use, topology conditions, modern protocol capability and limitations. This lab tests only IPv4 TCP. Same frontend/pool is necessary context, not a substitute for actual symmetry evidence.
- [Azure health probes](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-custom-probe-overview): probe-source behavior, health eligibility, established connections and unhealthy behavior. Observe runtime convergence rather than deriving an SLA from interval/threshold multiplication.
- [Load Balancer monitoring reference](https://learn.microsoft.com/en-us/azure/load-balancer/monitor-load-balancer-reference): DipAvailability BackendIPAddress dimension, VipAvailability distinction/delay and bandwidth metric limitation for UDR-directed internal-LB traffic.
- [Azure virtual network routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview): effective-route selection, virtual-appliance next hops and NIC/guest forwarding requirements.
- [Azure network security groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): stateful rules and service tags. Test actual effective rules and preserve original A/B tuples on NVA NICs.
- [Bastion and NSGs](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg): required separate management-subnet service rules.
- [Bastion native-client tunnel](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux): Standard native private management, existing approved extension/client prerequisites.
- [Linux conntrack sysctls](https://docs.kernel.org/networking/nf_conntrack-sysctl.html): `nf_conntrack_tcp_loose=0` disables midstream pickup. No conntrack replication is implemented.
- [Linux IP sysctls](https://docs.kernel.org/networking/ip-sysctl.html): IPv4 forwarding resets related configuration defaults; reverse-path filtering modes and forwarding/security knobs require explicit sequencing and verification.

## AzureRM provider source review

The code pins AzureRM **5.12.0** and Terraform **>=1.9,<2**. These exact-version documentation targets are supplied for future reproducible review:

- [5.12.0 LB](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/lb.html.markdown)
- [5.12.0 LB rule](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/lb_rule.html.markdown)
- [5.12.0 LB probe](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/lb_probe.html.markdown)
- [5.12.0 NIC backend association](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/network_interface_backend_address_pool_association.html.markdown)
- [5.12.0 Linux VM](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/linux_virtual_machine.html.markdown)
- [5.12.0 Bastion](https://github.com/hashicorp/terraform-provider-azurerm/blob/v5.12.0/website/docs/r/bastion_host.html.markdown)

The design brief's provider review and this lab's accessible official current-source review informed the LB/probe fields. The lab worker's pinned raw-file retrieval returned a cache miss; successful direct reads were the official [current LB](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/lb.html.markdown), [rule](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/lb_rule.html.markdown) and [probe](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/lb_probe.html.markdown) documentation. Current main-branch documentation can move. Do not describe those reads as an executed 5.12 provider schema check. In particular verify `probe_threshold`, `number_of_probes` and `no_healthy_backends_behavior="AllProbedDown"` against the actual pinned provider/API before any deployment; do not silently remove the all-unhealthy setting to make a plan pass.

No Terraform executable, provider binary/cache, lockfile or HCL parser was available here. Exact provider schema, HCL type behavior and Azure acceptance remain unvalidated even though the source contracts and future plan-only mock cases are supplied.

## Cost references

- [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Linux VMs](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/)
- [Load Balancer](https://azure.microsoft.com/en-us/pricing/details/load-balancer/)
- [Bastion](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/)
- [Managed disks](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)

Actual current region, SKU, currency, subscription offer and duration must be priced before approval. No quoted total or free-lab assumption is made.
