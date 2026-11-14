# Azure network security: Terraform labs

Companion code for the **Azure network security** video series. There is one folder per scenario. Each folder holds a Terraform lab with its own `README.md` and `LAB-GUIDE.md`; the lecture that runs the lab ("Running the lab") links here.

## Read this before you run anything
* **These labs create billable Azure resources** (firewalls, gateways, VMs and more). Run them in a sandbox subscription you control and **destroy them when you finish**.
* Costly options are behind variables that default to off. Read each folder's `README.md` first.
* Copy `terraform.tfvars.example` to `terraform.tfvars` and set your own values. Never commit `terraform.tfvars` or state files (the `.gitignore` excludes them).
* The code was written for teaching and checked with `terraform fmt` only. Check names and arguments against the current Azure provider documentation before relying on it.

## Scenarios
| # | Scenario | Folder |
|---|---|---|
| 1 | [Azure Firewall hub-and-spoke egress: one private VM, one route, one policy](01-firewall-egress/) | `01-firewall-egress/` |
| 2 | [Azure Firewall east-west inspection: two spokes, two routes, one firewall decision](02-east-west/) | `02-east-west/` |
| 3 | [Publishing a private service with Azure Firewall DNAT: one public port, two translations](03-public-ingress-dnat/) | `03-public-ingress-dnat/` |
| 4 | [Azure Firewall Premium TLS inspection: two TLS sessions, one CA from Key Vault, one URL rule](04-premium-tls/) | `04-premium-tls/` |
| 5 | [Azure Firewall Policy rule precedence: the rule that actually decides](05-rule-precedence/) | `05-rule-precedence/` |
| 6 | [Highly available NVAs behind an Azure internal load balancer with HA ports](06-nva-ha-ports/) | `06-nva-ha-ports/` |
| 7 | [Azure Route Server with BGP-peered Linux NVAs: the route is learned, the packet is carried](07-route-server-bgp/) | `07-route-server-bgp/` |
| 8 | [Inspect spoke-to-spoke traffic in a secured Virtual WAN hub with routing intent](08-vwan-private-inspection/) | `08-vwan-private-inspection/` |
| 9 | [Inspect Internet egress with a partner NVA integrated into a Virtual WAN hub](09-integrated-nva/) | `09-integrated-nva/` |
| 10 | [Virtual WAN Internet egress through a security partner provider](10-security-partner/) | `10-security-partner/` |
| 11 | [Transparent inspection with Azure Gateway Load Balancer](11-gateway-load-balancer/) | `11-gateway-load-balancer/` |
| 12 | [Hybrid inspection: branch traffic through a hub Azure Firewall, with two routes and one policy](12-hybrid-inspection/) | `12-hybrid-inspection/` |
| 13 | [Azure Firewall forced tunnelling to an upstream perimeter](13-forced-tunneling/) | `13-forced-tunneling/` |
| 14 | [Inspect traffic to a private endpoint with Azure Firewall](14-private-endpoint/) | `14-private-endpoint/` |
| 15 | [Layered WAF: Azure Front Door in front of Application Gateway](15-front-door-app-gateway-waf/) | `15-front-door-app-gateway-waf/` |
| 16 | [ExpressRoute multi-region peering and routing: steering traffic and surviving failures with two circuits](16-expressroute-multiregion/) | `16-expressroute-multiregion/` |
| 17 | [VNet addressing, subnets, peering and gateway transit](17-vnet-addressing-peering/) | `17-vnet-addressing-peering/` |
| 18 | [System routes, user-defined routes and effective routes: choosing, reading and diagnosing the next hop](18-system-routes-udr/) | `18-system-routes-udr/` |
| 19 | [NSG, application security groups and service tags: who may talk to whom, and which rule said so](19-nsg-asg-service-tags/) | `19-nsg-asg-service-tags/` |
| 20 | [Azure DNS and private DNS zones: who answers a name, who may read the zone, and how long a wrong answer lives](20-private-dns-zones/) | `20-private-dns-zones/` |
| 21 | [Hybrid DNS with Azure DNS Private Resolver: how names cross between Azure and on-premises](21-hybrid-dns-resolver/) | `21-hybrid-dns-resolver/` |
| 22 | [Outbound connectivity and SNAT: NAT Gateway, load balancer outbound rules and the firewall public IP](22-outbound-snat-natgw/) | `22-outbound-snat-natgw/` |
| 23 | [Azure Standard Load Balancer in depth](23-standard-load-balancer/) | `23-standard-load-balancer/` |
| 24 | [Choosing between Traffic Manager, Front Door, Application Gateway and Load Balancer](24-global-traffic-choice/) | `24-global-traffic-choice/` |
| 25 | [Azure Virtual Network Manager (AVNM): scopes, network groups, connectivity configurations and security admin rules](25-virtual-network-manager/) | `25-virtual-network-manager/` |
| 26 | [Site-to-site and point-to-site VPN design: gateways, IPsec, BGP over APIPA and remote access](26-vpn-s2s-p2s/) | `26-vpn-s2s-p2s/` |
| 27 | [Service endpoints, Private Endpoint and Private Link Service: three ways to keep traffic private, and what each one really prevents](27-endpoints-privatelink-service/) | `27-endpoints-privatelink-service/` |
| 28 | [Network observability and troubleshooting: Network Watcher, flow logs and Connection Monitor](28-observability-network-watcher/) | `28-observability-network-watcher/` |
| 29 | [Azure DDoS Protection: tiers, coverage, mitigation, telemetry and resilient design](29-ddos-protection/) | `29-ddos-protection/` |
| 30 | [AKS networking foundations: how pods get addresses, how traffic enters and leaves, and how to prove each path](30-aks-networking/) | `30-aks-networking/` |
| 31 | [IPv6 and dual stack on Azure: plan the addresses, repeat every control for both families, and prove each one](31-ipv6-dualstack/) | `31-ipv6-dualstack/` |
| 32 | [Virtual WAN site-to-site and ExpressRoute routing: hubs, route tables, association, propagation and labels](32-vwan-s2s-er-routing/) | `32-vwan-s2s-er-routing/` |
| 33 | [Secure management access: Azure Bastion and Just-in-Time VM access](33-bastion-jit/) | `33-bastion-jit/` |
| 34 | [ExpressRoute Direct, FastPath, Global Reach and resiliency](34-expressroute-direct-fastpath/) | `34-expressroute-direct-fastpath/` |
| 35 | [Azure Firewall Manager, policy inheritance and IP groups](35-firewall-manager-ip-groups/) | `35-firewall-manager-ip-groups/` |
| 36 | [Capstone: a multi-region enterprise network, designed, routed, inspected and broken](36-capstone-multiregion/) | `36-capstone-multiregion/` |
| 37 | [BGP path selection and selective routing across Azure VPN Gateway, Route Server, ExpressRoute and Virtual WAN](37-bgp-path-selection-selective-routing/) | `37-bgp-path-selection-selective-routing/` |
| 38 | [Container networking and security inspection: AKS egress through Azure Firewall, what the firewall sees, pod policy and ingress](38-container-security-inspection/) | `38-container-security-inspection/` |
| 42 | [AKS to AKS traffic enforcement with Palo Alto VM-Series firewalls, dynamic address groups, and cheaper layered alternatives](42-aks-paloalto-vmseries/) | `42-aks-paloalto-vmseries/` |
| 43 | [Inspecting Azure Load Balancer traffic with Palo Alto VM-Series (ILB, ELB, Gateway Load Balancer, SNAT, symmetry)](43-lb-paloalto-inspection/) | `43-lb-paloalto-inspection/` |
# azure-network-security
