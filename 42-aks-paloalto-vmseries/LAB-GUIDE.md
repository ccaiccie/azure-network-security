# Lab guide: AKS to AKS enforcement with VM-Series

Run the activities in order from the `terraform` folder. **Cost warning:** two VM-Series VMs (and their licence), a Standard load balancer, public IPs and two AKS nodes bill by the hour; destroy the lab the same day. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply`, no `az` and no `kubectl` command and no PAN-OS commit was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All three gates default to `false`. **You must accept the Marketplace terms yourself** (Activity 2). Never put keys, passwords or the PAN-OS API key in a file you share. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft and Palo Alto Networks documentation for limits, image names, versions and attribute names.

## Activity 1: Plan the free baseline and read the route design

**Goal.** Create only free objects: three VNets, four peerings, NSGs and two route tables with no routes yet. Confirm the peering flags.

**Exam skill:** Read peering settings and a route table association, and know why the routes are added only with the firewalls.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id` and `mgmt_source_cidr` (your own public address as a /32). Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 25 objects: 1 resource group, 3 VNets, 5 subnets, 4 peerings, NSGs and associations, 2 route tables and associations. No VM, no load balancer, no cluster. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete; outputs show the resource group name.

3. **Read the peering flags**: Forwarded traffic must be allowed on both sides of both peerings.

   ```bash
   az network vnet peering list -g cs42-rg --vnet-name cs42-spoke-a --query "[].{name:name,fwd:allowForwardedTraffic,gw:useRemoteGateways}" -o table
   ```

   Expect: One row `a-to-hub` with `fwd` True and `gw` False.

4. **Checkpoint**: Why is there no peering between the spokes? Answer: a direct peering adds a more specific system route that bypasses the firewall, and the design makes the hub the only path.

## Activity 2: Accept the Marketplace terms, deploy the firewall pair and the ILB

**Goal.** Open gate 1 to create two VM-Series VMs, the internal load balancer with HA ports and its probe, the routes, and make the probe healthy.

**Exam skill:** Explain the three NICs, IP forwarding, the probe from 168.63.129.16 and why both firewalls can look down together.

1. **Accept the Marketplace terms (one-time per subscription)**: Review the offer's terms and price in the Azure portal first, then accept. **This is a legal acceptance on your subscription; do it only if you agree.** The image publisher, offer, SKU and version are variables; check current Azure Marketplace and Palo Alto Networks documentation for the right values.

   ```bash
   az vm image terms show --publisher paloaltonetworks --offer vmseries-flex --plan byol
   # after reading the terms:
   az vm image terms accept --publisher paloaltonetworks --offer vmseries-flex --plan byol
   ```

   Expect: `accepted` becomes true. Alternatively set `accept_marketplace_terms = true` so Terraform creates the agreement (designed, not tested).

2. **Open gate 1**: In `terraform.tfvars` set `deploy_firewalls = true`, and set the admin password or SSH key variables through your own secret mechanism (never commit them). Two VMs, public IPs and a Standard load balancer bill by the hour.

   ```bash
   terraform plan -out=fw.tfplan
   terraform apply fw.tfplan
   ```

   Expect: About 30 objects are added: public IPs, 6 NICs, 2 VMs, the ILB with frontend 10.70.2.10, backend pool, HA ports rule, probe, and 4 routes. Outputs show the management addresses.

3. **Apply the PAN-OS configuration**: Use the bootstrap package (`bootstrap/`) or paste `bootstrap/panos-config.set.txt` into each firewall's CLI, then commit. It creates the zones, the interface profile for the probe, the virtual router routes, the objects, the DAGs, the security rules and the NAT rules.

   ```bash
   ssh admin@<fw1 management IP>
   configure
   # paste the set commands from bootstrap/panos-config.set.txt
   commit
   ```

   Expect: `Configuration committed successfully`. Repeat for fw2 (or push both from Panorama).

4. **Check the probe**: The ILB must report both backends healthy.

   ```bash
   az monitor metrics list --resource $(az network lb show -g cs42-rg -n cs42-ilb --query id -o tsv) --metric DipAvailability --interval PT1M -o table
   ```

   Expect: Average close to 100 when both trust NICs answer. If it is 0, check the NSG tag AzureLoadBalancer, the interface profile and the route for 168.63.129.16.

5. **Checkpoint**: Why can fw1 look healthy in its web UI while the ILB drops everything? Answer: the ILB judges only the probe; if the probe is blocked it removes both backends regardless of the firewall's own health.

## Activity 3: Create the two clusters with outbound type userDefinedRouting

**Goal.** Open gate 2 to create two small AKS clusters whose node subnets send egress and the other cluster's range to the ILB.

**Exam skill:** Read the network profile and effective routes, and know that the nodes join only because the firewall allows the AKS endpoints.

1. **Open gate 2**: Set `deploy_aks = true`. The lab refuses to plan without gate 1. Each cluster has one small node. Creation fails or times out if the firewall does not allow the required endpoints.

   ```bash
   terraform plan -out=aks.tfplan
   terraform apply aks.tfplan
   ```

   Expect: About 12 objects: two identities, role assignments and two clusters.

2. **Get credentials for both clusters**: Two contexts in your kubeconfig.

   ```bash
   az aks get-credentials -g cs42-rg -n cs42-aks-a --context aks-a --overwrite-existing
   az aks get-credentials -g cs42-rg -n cs42-aks-b --context aks-b --overwrite-existing
   kubectl --context aks-a get nodes -o wide
   ```

   Expect: A node Ready with an INTERNAL-IP in 10.71.0.0/22.

3. **Read the network profile**: Outbound type and the model.

   ```bash
   az aks show -g cs42-rg -n cs42-aks-a --query networkProfile -o json
   ```

   Expect: `outboundType` is `userDefinedRouting`; `networkPlugin` is `azure`.

4. **Read the node effective routes**: The NIC is in the node resource group.

   ```bash
   az network nic list -g MC_cs42-rg_cs42-aks-a_<region> --query "[0].name" -o tsv
   az network nic show-effective-route-table -g MC_cs42-rg_cs42-aks-a_<region> -n <nic name> -o table
   ```

   Expect: 0.0.0.0/0 and 10.72.0.0/16 with next hop 10.70.2.10, type VirtualAppliance.

5. **Checkpoint**: Why does outbound type UDR need the route before the cluster exists? Answer: AKS builds no outbound path, so nodes need one to pull images and reach the API server at creation.

## Activity 4: The allowed walk, the denied walk and the asymmetric failure

**Goal.** Deploy the apps, call orders from web through the firewall, see rule names in the PAN-OS log, then break symmetry on purpose.

**Exam skill:** Read a PAN-OS traffic log line, know which source address cluster B sees, and diagnose an asymmetric reply.

1. **Deploy the apps**: Orders in B with an internal LoadBalancer Service at 10.72.0.100, web and batch pods in A.

   ```bash
   kubectl --context aks-b apply -f manifests/apps-b.yaml
   kubectl --context aks-a apply -f manifests/apps-a.yaml
   kubectl --context aks-b -n orders get svc orders
   ```

   Expect: EXTERNAL-IP shows 10.72.0.100.

2. **Register the tags**: Rule 1 needs the web pod in the DAG; Activity 5 explains how. For now run the helper once.

   ```bash
   ./scripts/register-pod-tags.sh aks-a shop
   ```

   Expect: It prints one `registered <ip> <tags>` line per pod.

3. **Allowed call**: From the web pod.

   ```bash
   kubectl --context aks-a -n shop exec deploy/web -- curl -s -m 5 http://10.72.0.100:8080/
   ```

   Expect: The echo text. In PAN-OS: Monitor > Traffic shows rule `ew-shop-to-orders`, action allow, source 10.71.0.37, NAT source 10.70.2.4.

4. **Denied call**: From the batch pod, which is not in the DAG.

   ```bash
   kubectl --context aks-a -n shop exec deploy/batch -- curl -s -m 5 http://10.72.0.100:8080/
   ```

   Expect: Timeout. The traffic log shows rule `ew-deny-rest`, action deny.

5. **Break symmetry**: Set `b_reply_next_hop_override = "10.70.2.5"` and apply, and turn off the NAT rule on the firewalls. Repeat step 3.

   ```bash
   terraform apply -var b_reply_next_hop_override=10.70.2.5
   kubectl --context aks-a -n shop exec deploy/web -- curl -s -m 5 http://10.72.0.100:8080/
   ```

   Expect: Times out although the orders pod log shows the request. Remove the override to restore.

6. **Checkpoint**: Why does the pod in B log 10.70.2.4? Answer: the firewall's source NAT replaces the pod address so the reply returns to the firewall that owns the session.

## Activity 5: Dynamic address groups from Kubernetes labels

**Goal.** Give the firewall a read-only view of pod labels, register tags, watch a DAG fill, change a label and see the rule stop matching.

**Exam skill:** Explain tag to IP to DAG to rule, the stale window, and why the DAG cannot work for overlay pod addresses.

1. **Create the service account and read-only role**: A plugin or script needs get, list and watch on pods, services, namespaces and nodes (check current Palo Alto Networks documentation for the exact list). The manifest also creates a long-lived token Secret.

   ```bash
   kubectl --context aks-a apply -f manifests/rbac-pan-plugin.yaml
   kubectl --context aks-a -n kube-system get secret pan-plugin-token -o jsonpath='{.data.token}' | base64 -d > /dev/null && echo token-present
   ```

   Expect: `token-present`. Do not print or store the token in files you share.

2. **Register tags with the helper**: The script lists pods and Services with their labels and calls the PAN-OS XML API. Provide the key through an environment variable.

   ```bash
   export PAN_KEY=<api key from your secret store>
   ./scripts/register-pod-tags.sh aks-a shop fw1
   ```

   Expect: One line per pod; the firewall needs no commit for this.

3. **Read the DAG on the firewall**: From the firewall CLI.

   ```bash
   show object registered-ip all
   show object dynamic-address-group name dag-a-shop-web
   ```

   Expect: The web pod IPs appear with tags k8s-ns-shop and k8s-app-web; the DAG lists them.

4. **Change a label and watch the window**: Relabel the web pod, wait one sync interval, then call orders.

   ```bash
   kubectl --context aks-a -n shop label pod -l app=web app=web-v2 --overwrite
   kubectl --context aks-a -n shop exec deploy/web -- curl -s -m 5 http://10.72.0.100:8080/
   ```

   Expect: Before the next registration the rule still matches (stale tags). After a refresh that removes the old tags it times out: the traffic log shows `ew-deny-rest`.

5. **Quarantine by label**: Add `quarantine=true`; the script maps it to tag k8s-quarantine, which rule 2 denies.

   ```bash
   kubectl --context aks-a -n shop label pod -l app=web quarantine=true
   ./scripts/register-pod-tags.sh aks-a shop fw1
   ```

   Expect: Calls from that pod are denied by rule `quarantine`.

6. **Checkpoint**: Why would this fail in an overlay cluster? Answer: the firewall sees the node address, so a DAG of pod addresses never matches the packets.

## Activity 6: The cheap layer, comparisons and clean-up

**Goal.** Open gate 3 to add NSG rules and apply NetworkPolicies without the firewall's help, then destroy the lab.

**Exam skill:** Choose the lowest layer that can see the needed identity, and clean up costly resources in the right order.

1. **Open gate 3**: Set `enable_cheap_layer = true`: it creates NSG rules on both node subnets (free).

   ```bash
   terraform plan -out=cheap.tfplan
   terraform apply cheap.tfplan
   ```

   Expect: About 6 rule objects. The default AllowVnetInBound no longer lets A reach any port in B.

2. **Apply the policies**: Default deny, DNS allow, app allow and the egress policy.

   ```bash
   kubectl --context aks-a apply -f manifests/np-a.yaml
   kubectl --context aks-b apply -f manifests/np-b.yaml
   ```

   Expect: Calls from web to orders still work; calls from batch fail inside the cluster, before the firewall.

3. **Compare the evidence**: Which layer logged what.

   ```bash
   kubectl --context aks-a -n shop exec deploy/batch -- curl -s -m 5 http://10.72.0.100:8080/
   ```

   Expect: No firewall log row appears (the NetworkPolicy dropped it); with the policy removed the firewall logs the deny.

4. **Optional: Cilium FQDN policy**: Only with the Cilium dataplane and ACNS (check current docs).

   ```bash
   kubectl --context aks-a apply -f manifests/cnp-fqdn.yaml
   ```

   Expect: Egress to the named host works, others time out.

5. **Clean up**: Delete the workloads first so the load balancer frontends go away, then destroy through your own approved workflow.

   ```bash
   kubectl --context aks-a delete -f manifests/apps-a.yaml
   kubectl --context aks-b delete -f manifests/apps-b.yaml
   terraform plan -destroy -out=destroy.tfplan
   ```

   Expect: The plan lists everything to remove. Check that no VM, load balancer, public IP or cluster is left in the resource group afterwards.
