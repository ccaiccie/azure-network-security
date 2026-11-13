# Lab guide: AKS networking foundations

Run the activities in order from the `terraform` folder. **Cost warning:** an AKS node, the managed load balancer with its public IPs and the stand-in VM bill by the hour; destroy the lab the same day. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply`, no `az` and no `kubectl` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false`. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, SKU facts, image tags and attribute names.

## Activity 1: Plan the free baseline and do the address arithmetic

**Goal.** Create only free objects, then check the address plan for overlaps and size a node subnet with the helper script.

**Exam skill:** Apply the sizing formulas and the non-overlap rules before any cluster exists.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 12 objects: 1 resource group, 2 VNets, 3 subnets, 2 peerings, 1 NSG and its association, 1 private DNS zone and 1 record. No cluster, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with outputs `resource_group`, `aks_vnet_name` and empty cluster outputs.

3. **Check the address plan for overlap**: The script compares every range of the lab and prints any pair that overlaps.

   ```bash
   ./scripts/ipbudget.sh overlap
   SERVICE_CIDR=10.40.0.0/16 ./scripts/ipbudget.sh overlap
   ```

   Expect: The first run lists four ranges and the DNS IP and prints `no overlaps found`. The second run names the pair that overlaps (aks-vnet and service-cidr).

4. **Size a node subnet**: Ten nodes, one surge node, 30 pods per node, a /24 node subnet.

   ```bash
   ./scripts/ipbudget.sh node_subnet 10 1 30 24
   ./scripts/ipbudget.sh overlay 10 1 250 27
   ```

   Expect: Node subnet: 346 addresses needed, 251 usable in a /24, so it does NOT fit. Overlay: 16 addresses needed, 27 usable in a /27, so it fits.

5. **Checkpoint**: Why is a /24 enough for overlay but not for the node subnet model at the same node count? Answer: overlay reserves one address per node, the node subnet model reserves one per node plus one per possible pod.

## Activity 2: Deploy the cluster and read its network profile

**Goal.** Create one overlay cluster (gate 1) and read where nodes, pods and Services get their addresses.

**Exam skill:** Read the AKS network profile and tell node addresses, pod addresses and service addresses apart in real output.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_aks = true`. One small node and an AKS-managed load balancer bill by the hour until destroyed. Creation takes several minutes.

   ```bash
   terraform plan -out=aks.tfplan
   terraform apply aks.tfplan
   ```

   Expect: About 3 objects are added: a managed identity, a role assignment, and the cluster (the node resource group `MC_...` is created by AKS). Outputs now show `aks_name`.

2. **Get credentials and check the nodes**: This writes a context into your kubeconfig.

   ```bash
   az aks get-credentials -g aks30-rg -n aks30-aks --overwrite-existing
   kubectl get nodes -o wide
   ```

   Expect: One node, STATUS Ready, INTERNAL-IP in 10.40.1.0/24 (for example 10.40.1.4).

3. **Read the network profile**: The profile is the source of truth for the ranges.

   ```bash
   az aks show -g aks30-rg -n aks30-aks --query networkProfile -o json
   ```

   Expect: networkPlugin `azure`, networkPluginMode `overlay`, podCidr `10.244.0.0/16`, serviceCidr `172.20.0.0/16`, dnsServiceIp `172.20.0.10`, outboundType `loadBalancer`, loadBalancerSku `standard`. Field names may differ slightly by CLI version.

4. **See which pods have which address**: System pods that use the host network show the node IP. The others show pod CIDR addresses.

   ```bash
   kubectl get pods -n kube-system -o wide
   kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
   ```

   Expect: CoreDNS pods have 10.244.0.x addresses. Pods such as the masquerade agent show 10.40.1.4 (the node IP). The node's slice is 10.244.0.0/24. Exact pod names depend on the AKS version.

5. **Look at the DNS Service**: CoreDNS is reached through a ClusterIP at the DNS service IP.

   ```bash
   kubectl -n kube-system get svc kube-dns
   ```

   Expect: CLUSTER-IP 172.20.0.10, port 53 UDP and TCP.

6. **Checkpoint**: Why do some kube-system pods have the node's address? Answer: they use the host network, so they share the node's own IP instead of taking a pod CIDR address.

## Activity 3: Expose the echo app: ClusterIP, NodePort, LoadBalancer and internal

**Goal.** Create the four kinds of Service and see what each builds in Azure, and which client address the pod sees.

**Exam skill:** Choose a Service type, use the internal annotation and explain externalTrafficPolicy and the client IP.

1. **Deploy the app and a ClusterIP Service**: The app is `registry.k8s.io/echoserver:1.10`, which prints the caller address and headers.

   ```bash
   kubectl apply -f manifests/echo.yaml
   kubectl get pods -o wide
   kubectl get svc echo-clusterip
   ```

   Expect: Two echo pods with 10.244.x.x addresses. The Service has a CLUSTER-IP in 172.20.0.0/16 and no EXTERNAL-IP.

2. **Call it from a pod**: A small curl pod stays running so you can reuse it.

   ```bash
   kubectl run curl --image=curlimages/curl --restart=Never -- sleep 3600
   kubectl exec curl -- curl -s http://echo-clusterip/
   ```

   Expect: The echo text includes `Hostname:` of one of the pods and `client_address=` set to the curl pod's 10.244.x.x address: pod to pod keeps pod addresses. Image tags may change; check the registry.

3. **Add a NodePort Service**: Applies `svc-nodeport.yaml`.

   ```bash
   kubectl apply -f manifests/svc-nodeport.yaml
   kubectl get svc echo-nodeport
   ```

   Expect: PORT(S) shows 80:3xxxx/TCP, a port between 30000 and 32767 opened on every node. Nothing was created in Azure.

4. **Add a public LoadBalancer Service**: AKS builds a frontend IP, a rule and a probe.

   ```bash
   kubectl apply -f manifests/svc-lb-public.yaml
   kubectl get svc echo-lb -w
   curl -s http://<EXTERNAL-IP>/
   ```

   Expect: EXTERNAL-IP changes from pending to a public address after a minute or two. The echo text shows `client_address=` as a node address (10.40.1.x), not your public IP: policy Cluster hid it.

5. **Preserve the client IP with Local**: A second Service with `externalTrafficPolicy: Local`.

   ```bash
   kubectl apply -f manifests/svc-lb-local.yaml
   kubectl get svc echo-lb-local -w
   curl -s http://<EXTERNAL-IP-2>/
   ```

   Expect: `client_address=` shows your own public IP. With only one node and both pods on it, this works at once; with several nodes only nodes that hold a pod pass the probe.

6. **Add an internal LoadBalancer Service**: The annotation `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` makes the frontend private.

   ```bash
   kubectl apply -f manifests/svc-lb-internal.yaml
   kubectl get svc echo-lb-internal
   kubectl exec curl -- curl -s http://<INTERNAL-IP>/
   ```

   Expect: EXTERNAL-IP is a private address from snet-nodes (for example 10.40.1.5x). The curl pod reaches it; your laptop cannot.

7. **See what AKS built in Azure**: The load balancer is in the node resource group.

   ```bash
   NRG=$(az aks show -g aks30-rg -n aks30-aks --query nodeResourceGroup -o tsv)
   az network lb frontend-ip list -g "$NRG" --lb-name kubernetes -o table
   ```

   Expect: One frontend per LoadBalancer Service plus the outbound frontend, with names derived from the Services. Names and the number of rows depend on your Services.

8. **Checkpoint**: Which of your three LoadBalancer Services shows the real client address and why? Answer: echo-lb-local, because Local forwards only to pods on the receiving node and does not SNAT.

## Activity 4: Outbound, SNAT and the on-premises stand-in

**Goal.** Call a peered server from a pod, see the node address on the far side, then reproduce break/fix case 1 and prove it.

**Exam skill:** Explain overlay SNAT, write the right allow list for the far side and prove a deny with IP flow verify.

1. **Open gate 2**: Set `deploy_onprem_vm = true` and paste your public SSH key text into `admin_ssh_public_key`. A small VM bills by the hour.

   ```bash
   terraform plan -out=onprem.tfplan
   terraform apply onprem.tfplan
   terraform output onprem_vm_private_ip
   ```

   Expect: About 2 objects added. The output is 10.50.1.4. The VM's boot script starts a listener on tcp/8080 that answers with the caller's address.

2. **Call it from the pod**: The listener's answer includes `caller=` followed by the address it saw.

   ```bash
   kubectl exec curl -- curl -s -m 5 http://10.50.1.4:8080/
   ```

   Expect: `caller=10.40.1.4` (a node address from snet-nodes), not a 10.244.x.x pod address.

3. **Find the cluster's public egress address**: With outbound type loadBalancer the node resource group holds a public IP for outbound.

   ```bash
   NRG=$(az aks show -g aks30-rg -n aks30-aks --query nodeResourceGroup -o tsv)
   az network public-ip list -g "$NRG" -o table
   kubectl exec curl -- curl -s -m 5 https://api.ipify.org
   ```

   Expect: The address printed by the pod equals the outbound public IP in the list. (Any 'what is my IP' service will do; the service named here may change.)

4. **Break it: allow the pod CIDR only**: Set `onprem_allowed_source = "10.244.0.0/16"` in tfvars and apply. This is break/fix case 1.

   ```bash
   terraform apply
   kubectl exec curl -- curl -s -m 5 http://10.50.1.4:8080/
   ```

   Expect: The call times out (curl exit code 28) after 5 seconds: nothing is refused, the packet is dropped.

5. **Prove the deny with IP flow verify**: Test the tuple as the NSG sees it: source is the node address.

   ```bash
   az network watcher test-ip-flow -g aks30-rg --vm onprem-1 --direction Inbound --protocol TCP --local 10.50.1.4:8080 --remote 10.40.1.4:41234 -o json
   ```

   Expect: Access `Deny`, rule name ending in `deny-8080-other`. Repeat with `--remote 10.244.0.15:41234`: Allow, rule `allow-8080-from-list`. Rule names may carry a prefix.

6. **Fix it**: Set `onprem_allowed_source` back to 10.40.1.0/24 (the node subnet) and apply. Then call again.

   ```bash
   terraform apply
   kubectl exec curl -- curl -s -m 5 http://10.50.1.4:8080/
   ```

   Expect: `caller=10.40.1.4` again.

7. **Checkpoint**: Why did the NSG never see 10.244.0.15? Answer: the node masquerades overlay pod traffic that leaves the cluster, so the packet carries the node IP.

## Activity 5: DNS in the cluster and a private zone

**Goal.** Read a pod's resolver settings, reproduce a missing zone link (break/fix case 4), then fix it and read the CoreDNS log.

**Exam skill:** Diagnose CoreDNS, ndots, custom DNS and private zone links from inside a pod.

1. **Read the pod resolver settings**: These are what every pod gets.

   ```bash
   kubectl exec curl -- cat /etc/resolv.conf
   ```

   Expect: `nameserver 172.20.0.10`, a search list starting `default.svc.cluster.local svc.cluster.local cluster.local`, and `options ndots:5`.

2. **Start a DNS test pod and resolve a Service**: The image comes from the Kubernetes DNS debugging guide; check the tag.

   ```bash
   kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -- sleep 3600
   kubectl exec dnsutils -- nslookup echo-clusterip.default.svc.cluster.local
   ```

   Expect: Server 172.20.0.10 answers with the ClusterIP of echo-clusterip.

3. **Resolve the private zone name before the link**: The zone `lab30.internal` has an A record `db`, but `link_private_zone` is false.

   ```bash
   kubectl exec dnsutils -- nslookup db.lab30.internal
   ```

   Expect: `NXDOMAIN` (the exact words depend on the tool). CoreDNS is healthy; Azure DNS has no zone for this VNet.

4. **Link the zone and ask again**: Set `link_private_zone = true` and apply. The link takes a short while.

   ```bash
   terraform apply
   kubectl exec dnsutils -- nslookup db.lab30.internal
   ```

   Expect: `10.50.1.4`. If you still see NXDOMAIN, wait a minute: negative answers are cached.

5. **Turn on CoreDNS query logging**: The example ConfigMap adds the `log` plugin through `log.override`.

   ```bash
   kubectl apply -f manifests/coredns-custom.yaml
   kubectl -n kube-system rollout restart deployment coredns
   kubectl exec dnsutils -- nslookup db.lab30.internal
   kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
   ```

   Expect: Log lines for `db.lab30.internal.default.svc.cluster.local`, `db.lab30.internal.svc.cluster.local` and so on with NXDOMAIN, then the successful `db.lab30.internal.`: the ndots search list at work.

6. **Checkpoint**: Why were there four NXDOMAIN lines before the answer? Answer: the name has fewer than five dots, so every search suffix is tried first.

## Activity 6: Ingress with the application routing add-on and the client IP

**Goal.** Enable the managed NGINX ingress (gate 3), route to the echo app, and find where the client address survives.

**Exam skill:** Explain ingress client IP loss and the two fixes: Local policy and the X-Forwarded-For header.

1. **Open gate 3**: Set `enable_app_routing = true` and apply. The add-on adds an NGINX controller with its own LoadBalancer Service and public IP.

   ```bash
   terraform plan -out=ingress.tfplan
   terraform apply ingress.tfplan
   kubectl get pods -n app-routing-system
   kubectl get svc -n app-routing-system
   ```

   Expect: Controller pods Running. A Service named `nginx` of type LoadBalancer with an EXTERNAL-IP. Names and the namespace can differ by version; check current docs.

2. **Create the Ingress**: The class is `webapprouting.kubernetes.azure.com`.

   ```bash
   kubectl apply -f manifests/ingress.yaml
   kubectl get ingress echo
   ```

   Expect: ADDRESS is the same public IP as the `nginx` Service after a minute.

3. **Call it and read the headers**: The echo text prints the headers the app received.

   ```bash
   curl -s http://<INGRESS-IP>/
   ```

   Expect: `client_address=` is an address of the ingress controller or node, and the header `x-forwarded-for` holds your public IP: the proxy terminated your connection.

4. **See the Service policy of the controller**: This tells you whether the controller itself sees the real address.

   ```bash
   kubectl -n app-routing-system get svc nginx -o jsonpath='{.spec.externalTrafficPolicy}'
   ```

   Expect: `Cluster` or `Local`, depending on the add-on version (check current docs). With `Cluster` the controller sees a node address; the app is better off reading `x-forwarded-for` as long as the controller is configured to trust the header in front of it.

5. **Checkpoint**: Where can the app read the real visitor address in this path? Answer: in the `X-Forwarded-For` header that NGINX adds, not in the TCP source address.

## Activity 7: API access, subnet exhaustion checks and clean-up

**Goal.** Read the API server access settings, check the real subnet usage, and destroy everything in the right order.

**Exam skill:** Choose an API access option, diagnose subnet fullness with one command and stop the billing safely.

1. **Read the API server access profile**: A public cluster with no authorized ranges is open to every source.

   ```bash
   az aks show -g aks30-rg -n aks30-aks --query "{fqdn:fqdn,private:apiServerAccessProfile.enablePrivateCluster,ranges:apiServerAccessProfile.authorizedIpRanges}" -o json
   ```

   Expect: A public FQDN, `private` false or null, `ranges` null or empty. To restrict, set `api_authorized_ranges = ["<your public IP>/32"]` and apply; use your real address, not the documentation example.

2. **Count the used addresses of the node subnet**: Each node NIC (and each pod in node subnet mode) is an IP configuration.

   ```bash
   az network vnet subnet show -g aks30-rg --vnet-name aks30-vnet -n snet-nodes --query "{prefix:addressPrefix,used:length(ipConfigurations)}" -o json
   ```

   Expect: A /24 prefix and `used` equal to the node count plus any internal load balancer frontends. Compare with `./scripts/ipbudget.sh overlay 10 1 250 24`.

3. **Optional: add a second pool in a second subnet**: Gate 4 adds a node pool in snet-nodes2. It bills by the hour.

   ```bash
   terraform apply
   kubectl get nodes -o wide
   ```

   Expect: A second node with an address in 10.40.2.0/24, in the same overlay cluster, with a pod slice from the same pod CIDR.

4. **Delete the Services first**: AKS removes the Azure frontends and public IPs it created when the Services go.

   ```bash
   kubectl delete -f manifests/ --ignore-not-found
   kubectl delete pod curl dnsutils --ignore-not-found
   ```

   Expect: Services, Ingress and Deployment deleted. In the portal the node resource group's load balancer keeps only the outbound frontend.

5. **Destroy the lab**: Only through your own approved workflow. Read the plan: it must list the cluster, the VMs and the baseline.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: All resources destroyed. `az group list -o table` no longer shows `aks30-rg` or its `MC_` group. Delete the local kubeconfig context with `kubectl config delete-context aks30-aks`.

6. **Checkpoint**: Why delete the Services before the cluster? Answer: the cluster controller owns the Azure frontends and public IPs it made for them, and deleting the Services lets it clean up while it still runs.
