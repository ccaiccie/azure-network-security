# East-west operator evidence record

**Template only. No Azure result was captured while drafting.** Keep expected and observed results separate.

- Operator, authorized subscription/region/resource group:
- Deployment and test window UTC:
- Terraform/AzureRM version and lock-file verification:
- Concrete image version:
- Actual F / firewall policy ID:
- A/B and optional C actual VM, NIC and private IP identities:
- Experiment flags: explicit_remote_routes=true, return_route_blackhole=false; enable_same_vnet=false (or true for C); same_vnet_return_route_enabled=true:

| Check | Status | Actual observation | Evidence path / case / UTC |
|---|---|---|---|
| Private subnets, no workload public IPs | NOT RUN | | |
| Four connected forwarded-traffic peerings | NOT RUN | | |
| A effective route to B selects F | NOT RUN | | |
| B effective route to A selects F | NOT RUN | | |
| Optional next-hop diagnostics both ways | NOT RUN | Requires existing authorized Network Watcher | |
| Effective NSGs permit all three tested new connections | NOT RUN | | |
| A:8080 owned local service and JSON identity ready | NOT RUN | | |
| B:8080 owned local service and JSON identity ready | NOT RUN | | |
| B:8081 owned local service and JSON identity ready | NOT RUN | | |
| A→B:8080 HTTP200 / original source / named Allow | NOT RUN | | |
| A→B:8081 no response / named Deny / readiness+NSG evidence | NOT RUN | | |
| New B→A:8080 named Deny / readiness+NSG evidence | NOT RUN | | |
| Repeat A→B:8080 after reverse denial | NOT RUN | | |
| Optional bounded endpoint capture | NOT RUN | Not automatically performed; no capture utility installed | |
| Optional default-route-only variant | NOT RUN | Must not assume removing /16 breaks flow | |
| Optional B return /32→None blackhole | NOT RUN | Route failure, not a firewall denial | |
| Rollback restores baseline routes and all traffic evidence | NOT RUN | | |
| Cleanup state empty / group absent / billable resources removed | NOT RUN | | |
| Optional C: private app-VNet subnet/VM/NIC identity | NOT RUN | enable_same_vnet=true required | |
| Optional C: A→C /24 and C→A /24 select F | NOT RUN | A /0 and C /0 alone are insufficient | |
| Optional C: effective NSGs permit three test paths | NOT RUN | | |
| Optional C: owned 8080 and 8081 services/JSON ready | NOT RUN | Also refresh A:8080 readiness | |
| Optional A→C:8080 HTTP200 / original source / named Allow | NOT RUN | allow-app-to-same-vnet | |
| Optional A→C:8081 no response / named Deny | NOT RUN | deny-same-vnet-alternate-port; readiness+NSGs required | |
| Optional new C→A:8080 no response / named Deny | NOT RUN | deny-same-vnet-reverse-new; readiness+NSGs required | |
| Optional repeat A→C:8080 after reverse denial | NOT RUN | Full positive criteria | |
| Optional C return /24 removal selects local-VNet /16 | NOT RUN | Asymmetry, not a guaranteed timeout or Deny | |
| Optional C-enabled rollback restores both /24s and all evidence | NOT RUN | Keep C enabled; restore return flag | |
| Optional C removal / two-VM restoration | NOT RUN | Separate reviewed change; can replace A/B VMs | |

Only PASSED, FAILED, INCONCLUSIVE or NOT RUN are valid statuses. Negative curl results are inconclusive without recent remote-listener readiness, permitting effective NSGs and the corresponding named firewall Deny. Server source identity alone does not establish the path. Missing optional diagnostics must remain NOT RUN.

## Issues, restrictions and unresolved results

## Retained evidence and cleanup confirmation
