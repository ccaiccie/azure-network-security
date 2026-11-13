# Lab guide: Container networking and security inspection

Run the activities in order from the `terraform` folder. **Cost warning:** an Azure Firewall (Basic, the smallest SKU), its public IPs, an AKS node and the Log Analytics ingest bill by the hour or by volume; destroy the lab the same day. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply`, no `az` and no `kubectl` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false`. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, SKU facts, image tags and attribute names.

## Activity 1: Plan the free baseline and read the route design

**Goal.** Create only free objects: two VNets, peering, a route table and its association. Confirm that the route table has no default route yet.

**Exam skill:** Read a route table and its subnet association, and know why the route is added only after the firewall exists.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 10 objects: 1 resource group, 2 VNets, 3 subnets, 2 peerings, 1 route table and its association. No firewall, no cluster. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. Outputs `resource_group` and empty firewall and cluster outputs.

3. **Read the route table**: The table is attached to the node subnet but holds no routes yet, because a route needs a firewall address.

   ```bash
   az network route-table show -g cs38-rg -n cs38-nodes-rt --query "{routes:routes[].name,subnets:subnets[].id}" -o json
   ```

   Expect: `routes` is empty and `subnets` lists snet-nodes.

4. **Checkpoint**: Why is the default route created only when the firewall exists? Answer: its next hop is the firewall's private IP, which Azure assigns at deployment, so the route reads it from the firewall resource instead of a typed address.

## Activity 2: Deploy the firewall and read its rules

**Goal.** Open gate 1 to create the firewall, its policy with the AKS rules and the two user routes, then read each one back.

**Exam skill:** Read a firewall policy rule collection group and tell a network rule from an application rule.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_firewall = true`. The Basic firewall bills by the hour, plus two public IPs. Creation takes several minutes.

   ```bash
   terraform plan -out=fw.tfplan
   terraform apply fw.tfplan
   ```

   Expect: About 8 objects are added: 2 public IPs, the policy, one rule collection group, the firewall, and 2 routes. Output `firewall_private_ip` shows an address from 10.60.0.0/26 (for example 10.60.0.4).

2. **Read the routes**: The next hop must equal the firewall's private IP.

   ```bash
   az network route-table route list -g cs38-rg --route-table-name cs38-nodes-rt -o table
   terraform output firewall_private_ip
   ```

   Expect: Route `default-to-firewall` 0.0.0.0/0 with next hop type VirtualAppliance and the same address as the output; route `firewall-pip-direct` with the firewall's public IP /32 and next hop Internet.

3. **Read the rules**: The policy holds the AKS FQDN tag rule and one test rule.

   ```bash
   az network firewall policy rule-collection-group collection list -g cs38-rg --policy-name cs38-fwpolicy --rule-collection-group-name aks -o json
   ```

   Expect: An application rule collection with a rule using the FQDN tag `AzureKubernetesService` on tcp 80 and 443, and a second rule for the test domain, both with source 10.61.1.0/24.

4. **Checkpoint**: Which rule type matches by name? Answer: the application rule. A network rule matches by address, port and protocol, and matches by name only when the DNS proxy is enabled (check current docs for your SKU).

## Activity 3: Create the cluster with outbound type userDefinedRouting

**Goal.** Open gate 2 and create one overlay cluster whose egress follows the route table to the firewall.

**Exam skill:** Read the network profile and recognise a UDR cluster: no outbound load balancer or public IP is built.

1. **Open gate 2**: In `terraform.tfvars` set `deploy_aks = true`. The lab refuses to plan this without gate 1. One small node bills by the hour. Creation takes several minutes and fails or times out if the nodes cannot reach the registry through the firewall.

   ```bash
   terraform plan -out=aks.tfplan
   terraform apply aks.tfplan
   ```

   Expect: About 4 objects are added: a managed identity, two role assignments and the cluster. Outputs show `aks_name`.

2. **Get credentials and check the node**: This writes a context into your kubeconfig.

   ```bash
   az aks get-credentials -g cs38-rg -n cs38-aks --overwrite-existing
   kubectl get nodes -o wide
   ```

   Expect: One node, STATUS Ready, INTERNAL-IP in 10.61.1.0/24 (for example 10.61.1.4).

3. **Read the network profile**: The profile shows the model and the outbound type.

   ```bash
   az aks show -g cs38-rg -n cs38-aks --query networkProfile -o json
   ```

   Expect: networkPlugin `azure`, networkPluginMode `overlay`, podCidr `10.244.0.0/16`, outboundType `userDefinedRouting`, networkPolicy as set in `network_policy`.

4. **Read the node's effective routes**: The node NIC lives in the node resource group. Replace the placeholders with your values.

   ```bash
   NRG=$(terraform output -raw node_resource_group)
   NIC=$(az network nic list -g "$NRG" --query "[0].name" -o tsv)
   az network nic show-effective-route-table -g "$NRG" -n "$NIC" -o table
   ```

   Expect: A row 0.0.0.0/0 with next hop type VirtualAppliance and the firewall's private IP, and a row for the firewall public IP /32 with next hop Internet.

5. **Checkpoint**: Where is the outbound load balancer? Answer: with userDefinedRouting AKS builds none for egress, so the route table alone decides how traffic leaves; check current docs for what the API server path needs.

## Activity 4: Prove what the firewall sees: node IP, not pod IP

**Goal.** Deploy a client pod, call an allowed and a blocked domain, then read the firewall log and see which source address it recorded.

**Exam skill:** Predict the source address a firewall logs for overlay pods, and fix a rule written for the wrong range.

1. **Open gate 4 and deploy the workloads**: Gate 4 creates a Log Analytics workspace and a diagnostic setting for the firewall (small ingest cost). Then apply the manifests.

   ```bash
   terraform apply -var enable_diagnostics=true
   kubectl apply -f manifests/echo.yaml
   kubectl get pods -n lab -o wide
   ```

   Expect: Namespace `lab` with `client` and two `echo` pods. Pod IPs are in 10.244.0.0/16, and the NODE column shows the node name.

2. **Call an allowed and a blocked domain**: The script prints OK with the HTTP code or BLOCKED.

   ```bash
   ./scripts/egress-probe.sh lab client https://example.com https://www.example.org
   ```

   Expect: `https://example.com` OK (rule 300). `https://www.example.org` BLOCKED: no rule matches, so the default deny applies.

3. **Read the firewall log**: Logs may take several minutes to appear. Use Log Analytics, then the query below.

   ```bash
   az monitor log-analytics query -w $(terraform output -raw workspace_id) --analytics-query "AZFWApplicationRule | where TimeGenerated > ago(30m) | project TimeGenerated, SourceIp, Fqdn, Action, Rule | order by TimeGenerated desc | take 20" -o table
   ```

   Expect: Rows with `SourceIp` 10.61.1.4 (the node) and `Fqdn` example.com `Allow`, and www.example.org `Deny`. No row shows 10.244.0.15.

4. **Break it on purpose: write the rule for the pod range**: Case 2 of the break/fix section. Change the rule source to the pod CIDR and apply.

   ```bash
   terraform apply -var egress_rule_source=10.244.0.0/16
   ./scripts/egress-probe.sh lab client https://example.com
   ```

   Expect: BLOCKED now. The log shows `Deny` with SourceIp 10.61.1.4: the packet carries the node address, so the pod-range rule never matches.

5. **Restore the rule**: Set the source back to the node subnet.

   ```bash
   terraform apply -var egress_rule_source=10.61.1.0/24
   ```

   Expect: `https://example.com` is OK again.

6. **Checkpoint**: How would a per-pod rule work? Answer: not in overlay mode. Use the node subnet model so pods keep VNet addresses, or Cilium policy inside the cluster, or accept per-node rules.

## Activity 5: NetworkPolicy: default deny and the DNS trap

**Goal.** Apply a default-deny policy, watch name resolution fail, then add the DNS allow and one app allow.

**Exam skill:** Write a deny-all policy and the two allows that keep a namespace working, and prove each with a test by name and by IP.

1. **Confirm the policy engine and the baseline**: The cluster needs a policy engine (`network_policy` set to azure, calico or cilium). Check that the client reaches echo by name.

   ```bash
   az aks show -g cs38-rg -n cs38-aks --query networkProfile.networkPolicy -o tsv
   kubectl exec -n lab client -- curl -s -m 3 http://echo/
   ```

   Expect: The engine name. Then the echo text, because without a policy every pod can reach every pod.

2. **Apply the default deny**: One policy selects every pod in `lab` and denies ingress and egress.

   ```bash
   kubectl apply -f manifests/np-default-deny.yaml
   kubectl exec -n lab client -- curl -s -m 3 http://echo/
   ```

   Expect: The call times out (no output, exit code 28), and a lookup by name fails first.

3. **Allow only the app path and test by IP**: The allow-app policy lets client reach echo on tcp/8080. A call by name still fails because DNS is blocked.

   ```bash
   kubectl apply -f manifests/np-allow-app.yaml
   ECHOIP=$(kubectl get svc echo -n lab -o jsonpath='{.spec.clusterIP}')
   kubectl exec -n lab client -- curl -s -m 3 http://$ECHOIP/
   kubectl exec -n lab client -- curl -s -m 3 http://echo/
   ```

   Expect: The call by ClusterIP returns the echo text; the call by name still times out.

4. **Allow DNS to kube-system**: The allow-dns policy permits udp and tcp 53 to the CoreDNS pods.

   ```bash
   kubectl apply -f manifests/np-allow-dns.yaml
   kubectl exec -n lab client -- curl -s -m 3 http://echo/
   ```

   Expect: The echo text again, by name.

5. **Optional: a Cilium FQDN policy**: Only if the cluster runs the Cilium dataplane with the Advanced Container Networking Services feature (check current docs and pricing). It allows one domain and nothing else for the client.

   ```bash
   kubectl apply -f manifests/cnp-fqdn.yaml
   ./scripts/egress-probe.sh lab client https://example.com https://www.example.org
   ```

   Expect: If the feature is active, only example.com is OK. If the policy kind is unknown, the feature is not enabled; skip this step.

6. **Checkpoint**: Why did names fail but the ClusterIP work? Answer: the deny-all policy also blocked egress to CoreDNS in kube-system, and a lookup is a connection like any other.

## Activity 6: Ingress by firewall DNAT, the asymmetric public Service, and clean-up

**Goal.** Publish the echo app through an internal load balancer and a firewall DNAT, then create a public Service on the UDR cluster to see the asymmetric reply, fix it, and destroy the lab.

**Exam skill:** Predict the client address the app sees behind a DNAT, and diagnose a public Service on a UDR cluster.

1. **Open gate 3 and the internal Service**: The DNAT rule sends the firewall's public tcp/80 to the internal load balancer address 10.61.1.100.

   ```bash
   kubectl apply -f manifests/svc-ilb.yaml
   terraform apply -var enable_dnat=true
   terraform output firewall_public_ip
   ```

   Expect: The Service `echo-ilb` has EXTERNAL-IP 10.61.1.100 and the output shows the firewall public IP.

2. **Call through the DNAT from your computer**: Use the firewall public IP.

   ```bash
   curl -s -m 5 http://$(terraform output -raw firewall_public_ip)/
   ```

   Expect: The echo text. Read `client_address=`: it is an address from the firewall subnet, not your public IP, because the firewall SNATs a DNAT flow (check current docs).

3. **Create a public Service and watch it fail**: The UDR cluster still builds a public frontend for a public Service, but the reply is routed to the firewall.

   ```bash
   kubectl apply -f manifests/svc-lb-public.yaml
   kubectl get svc echo-lb -n lab
   curl -s -m 5 http://<EXTERNAL-IP>/
   ```

   Expect: An EXTERNAL-IP appears, and the curl times out. The pod log (`kubectl logs`) shows the request arrived.

4. **Fix it with a route for your client range**: Set `bypass_client_cidr` to your own public address as a /32. The route sends replies to that address straight to the Internet.

   ```bash
   terraform apply -var bypass_client_cidr=<your-public-ip>/32
   curl -s -m 5 http://<EXTERNAL-IP>/
   ```

   Expect: The echo text, with `client_address` equal to your public IP.

5. **Delete the workloads, then destroy**: Delete the Services first so AKS removes its frontends, then destroy with Terraform and verify.

   ```bash
   kubectl delete -f manifests/ --ignore-not-found
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   az group list --query "[?starts_with(name,'cs38') || starts_with(name,'MC_cs38')].name" -o tsv
   ```

   Expect: The last command prints nothing.

6. **Checkpoint**: Why does the reply fail but the DNAT call work? Answer: in the DNAT flow the firewall saw the request and holds the session, so the reply matches; in the public Service flow the request never touched the firewall.
