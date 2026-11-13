# Endpoint diagnosis checklist (designed, not tested)

Ask in this order. Stop at the first answer that explains the symptom.

1. What does the service name resolve to from the client? `getent hosts NAME` on the VM.
   A private address in the endpoint subnet means the private path; a public address means the public path (service endpoint or Internet).
2. Public address: is the privatelink zone linked to this VNet? Is the subnet a VNet rule? Does the subnet have the service endpoint (`./scripts/diagnose.sh subnets`)?
3. Private address: is the connection Approved (`./scripts/diagnose.sh conns`, `pls`)? Pending and Rejected carry no data.
4. Firewall and public access: default action, public network access and bypass (`./scripts/diagnose.sh acct`). 403 usually means the firewall, a timeout usually means the network (route, NSG, approval).
5. Routes: `./scripts/diagnose.sh routes VM` shows ServiceEndpoint and private endpoint next hops. A service endpoint route beats a 0.0.0.0/0 UDR.
6. NSG and UDR on endpoint traffic: check the network policies value of the endpoint subnet; with policies Disabled an NSG rule on that subnet is not applied (check current Microsoft docs).
7. Private Link Service: backend address seen is a NAT IP unless proxy protocol is on; if connections fail only under load, count the NAT IPs and ports.
8. Check current Microsoft docs for limits, region support and the trusted-service list before relying on them.
