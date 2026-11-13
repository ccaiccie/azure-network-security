# Lab guide: Choosing between Traffic Manager, Front Door, Application Gateway and Load Balancer

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read each plan first. All four gates default to `false`. Keep gates you have opened set to `true` in `terraform.tfvars`: the `-var` options in the activities override only the values they name. Addresses are RFC 1918 and RFC 5737 examples. Check current Microsoft docs and the provider docs for limits, pricing, SKUs, attribute names and CLI output.

## Activity 1: Plan the free baseline and read the NSG rules

**Goal.** Create the free network objects and read the Application Gateway subnet rules, including the mandatory management range.

**Exam skill:** Know that an Application Gateway v2 subnet is dedicated and that its NSG must allow GatewayManager on ports 65200 to 65535.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file, set `subscription_id` and `my_ip_cidr` (your public address as a /32). Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds about 9 objects: a random suffix, the resource group, the VNet, two subnets, two NSGs and two associations. No VM, no gateway. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete, with the output `resource_group` set to gtc24-rg.

3. **Read the gateway subnet rules**: These rules matter later: without the first one the gateway cannot be managed.

   ```bash
   az network nsg rule list -g gtc24-rg --nsg-name gtc24-nsg-agw -o table
   ```

   Expect: Three rules: `allow-gatewaymanager` (65200-65535), `allow-azurelb` and `allow-http-clients` (port 80, with your address and two service tags).

4. **Checkpoint**: Why does the gateway subnet need its own subnet and a management-port rule? Answer: the v2 gateway instances are managed by the platform over that port range, and the subnet may hold only gateway instances; a blocked range leaves the gateway unhealthy.

## Activity 2: Deploy the backends and the load balancer

**Goal.** Open gate 1 and see that a layer 4 path keeps the client address all the way to the web server.

**Exam skill:** State that a Standard Load Balancer does not change the source address and does not read HTTP.

1. **Open gate 1**: In `terraform.tfvars` set `deploy_backends = true` and paste the text of your public key into `admin_ssh_public_key`. The VMs and the balancer bill by the hour until destroyed; check current pricing.

   ```bash
   terraform plan -out=backends.tfplan
   terraform apply backends.tfplan
   ```

   Expect: About 10 objects are added: a public IP, the load balancer with its pool, probe and rule, two NICs, two associations and two VMs. The VMs install nginx at first boot, so allow a few minutes.

2. **Ask the load balancer what the backend sees**: Run it several times. A new connection uses a new source port, so the flow hash can pick either server.

   ```bash
   LB=$(terraform output -raw lb_fqdn)
   for i in 1 2 3 4; do curl -s http://$LB/ | head -3; echo; done
   ```

   Expect: `host=web1` or `host=web2`, and `remote_addr` is your own public address. No proxy is in the path.

3. **Use the helper**: The helper prints the same page with the status line. Set the variable first.

   ```bash
   export LB_FQDN=$(terraform output -raw lb_fqdn)
   ./scripts/verify.sh lb
   ```

   Expect: `HTTP/1.1 200 OK`, then the `host=` and `remote_addr=` lines.

4. **Checkpoint**: Why is `remote_addr` your address and not the balancer's? Answer: the balancer forwards the flow to a backend without terminating it, so the packet's source address is unchanged.

## Activity 3: Add the Application Gateway and read the client IP

**Goal.** Open gate 2 and compare what the web server sees through a layer 7 proxy.

**Exam skill:** Explain that a proxy opens a new connection, so the backend's peer is the proxy and the client is in X-Forwarded-For.

1. **Open gate 2**: Set `deploy_app_gateway = true`. The gateway bills by the hour plus capacity units; check current pricing. Creation can take several minutes.

   ```bash
   terraform plan -out=appgw.tfplan
   terraform apply appgw.tfplan
   ```

   Expect: About 2 objects are added: a public IP and the gateway with its listener, rule, probe, backend setting and rewrite set.

2. **Check the backend health**: The gateway only forwards to servers it marks Healthy.

   ```bash
   export AGW_NAME=gtc24-agw RG=gtc24-rg
   ./scripts/verify.sh health
   ```

   Expect: Both `10.24.2.11` and `10.24.2.12` show `Healthy`.

3. **Ask through the gateway**: Compare with Activity 2.

   ```bash
   export APPGW_FQDN=$(terraform output -raw appgw_fqdn)
   ./scripts/verify.sh appgw
   ```

   Expect: `remote_addr=10.24.1.x` (an address in the gateway subnet), `x_forwarded_for=` your address (the format may include a port; check current docs), and the response header `X-Lab-Tier: application-gateway` added by the rewrite set.

4. **Checkpoint**: Which setting decides whether the gateway reaches a server? Answer: the backend health from the probe named in the backend setting; an unhealthy server gets no traffic.

## Activity 4: Add Front Door and lock the gateway to it

**Goal.** Open gate 3, read the headers Front Door adds, then restrict the gateway subnet to Front Door and Traffic Manager sources.

**Exam skill:** Name X-Azure-ClientIP and X-Forwarded-For, and explain why a service-tag rule alone does not prove the request came from your own profile.

1. **Open gate 3**: Set `deploy_front_door = true`. Front Door Standard has a base fee; check current pricing. Propagation to the edge can take several minutes after the apply finishes.

   ```bash
   terraform plan -out=afd.tfplan
   terraform apply afd.tfplan
   ```

   Expect: About 5 objects are added: the profile, an endpoint, an origin group, an origin and a route.

2. **Ask through Front Door**: The first requests may fail with a 404 while the endpoint is still being deployed.

   ```bash
   export AFD_HOST=$(terraform output -raw front_door_hostname)
   ./scripts/verify.sh afd
   ```

   Expect: `x_azure_clientip=` your address and `x_forwarded_for=` your address followed by an edge address; `remote_addr` is in 10.24.1.0/24. The response carries an `X-Azure-Ref` header.

3. **Lock the gateway subnet**: Set `appgw_only_from_front_door = true` and apply. This removes your address from the gateway subnet rule.

   ```bash
   terraform apply -var appgw_only_from_front_door=true
   curl -s --max-time 8 http://$(terraform output -raw appgw_fqdn)/ || echo blocked
   ./scripts/verify.sh afd
   ```

   Expect: The direct call to the gateway times out (`blocked`). The call through Front Door still returns the page.

4. **Checkpoint**: Is the service tag enough? Answer: no. The tag covers every Front Door profile, so a different customer's profile could point at your gateway. Also check the X-Azure-FDID header against your own profile id.

## Activity 5: Add Traffic Manager and read the DNS answer

**Goal.** Open gate 4 and read the CNAME, the TTL and the effect of changing the routing method.

**Exam skill:** Describe what a priority and a weighted profile return, and explain that the answer carries a TTL.

1. **Open gate 4**: Set `deploy_traffic_manager = true` and set `appgw_only_from_front_door` back to `false` so the probes and your tests can reach the gateway. Traffic Manager bills by DNS queries and endpoints; check current pricing.

   ```bash
   terraform apply -var appgw_only_from_front_door=false -var deploy_traffic_manager=true
   ```

   Expect: About 3 objects are added: the profile and two external endpoints. Endpoint status shows `Online` after the first probes.

2. **Read the answer**: Use `dig` so you can see the TTL.

   ```bash
   export TM_FQDN=$(terraform output -raw traffic_manager_fqdn)
   dig +noall +answer $TM_FQDN
   ```

   Expect: A CNAME to the gateway name (priority 1) with a TTL of 30, then its address.

3. **Switch to weighted**: Both endpoints have weight 100, so answers should alternate over many queries.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var tm_routing_method=Weighted
   for i in 1 2 3 4 5 6; do dig +short $TM_FQDN | head -1; sleep 31; done
   ```

   Expect: A mix of the gateway name and the load balancer name. Your local resolver may cache each answer for up to the TTL, which is why the loop waits 31 seconds.

4. **Back to priority**: Restore the first method.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var tm_routing_method=Priority
   ```

   Expect: The answer is the gateway name again.

## Activity 6: Break the gateway's probe path and time the failover

**Goal.** Make the gateway's probe ask for a path that does not exist, see the 502, and measure how long Traffic Manager takes to start answering with the load balancer.

**Exam skill:** Diagnose a 502 from backend health, and break failover time into probing time plus DNS caching time.

1. **Start the timer in a second terminal**: It asks the profile name every 5 seconds and prints the time and the answer.

   ```bash
   export TM_FQDN=$(terraform output -raw traffic_manager_fqdn)
   ./scripts/failover-timer.sh 5 80
   ```

   Expect: Lines such as `14:02:05  ttl=30 CNAME <appgw name>`. Leave it running.

2. **Break the probe path**: Set `appgw_probe_path` to a path the VMs do not serve.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var appgw_probe_path=/health
   ```

   Expect: One object changes in place: the gateway. Note the time.

3. **Diagnose the symptom**: Run the checks in order: status code, backend health, then the path.

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://$(terraform output -raw appgw_fqdn)/
   ./scripts/verify.sh health
   ```

   Expect: `502`, then both servers `Unhealthy`. The servers are fine; the probe asks for `/health`, which returns 404.

4. **Watch the answer change**: Traffic Manager probes `/healthz` through the gateway, which now answers 502, so ep-appgw is marked degraded after the tolerated failures.

   ```bash
   # in the timer terminal, wait for the change
   ./scripts/verify.sh tm
   ```

   Expect: The timer switches to the load balancer name. With a 30 second interval and 3 tolerated failures, expect on the order of 2 minutes plus up to one TTL. Write down your measured time.

5. **Repair**: Put the path back and wait for the endpoint to return.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var appgw_probe_path=/healthz
   ```

   Expect: The gateway shows `Healthy` again and, after the next probes, the timer returns to the gateway name.

## Activity 7: Lengthen the TTL and measure again

**Goal.** Repeat the failover with a TTL of 300 seconds and compare the result with Activity 6.

**Exam skill:** Explain why failover is probing time plus caching time, and why a long TTL hurts.

1. **Set a long TTL**: Apply the longer TTL and let resolvers pick it up.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var tm_ttl_seconds=300
   dig +noall +answer $TM_FQDN
   ```

   Expect: The CNAME now shows a TTL up to 300.

2. **Break again and time it**: Start the timer in a second terminal, then repeat the break from Activity 6.

   ```bash
   ./scripts/failover-timer.sh 10 80
   terraform apply -var deploy_traffic_manager=true -var tm_ttl_seconds=300 -var appgw_probe_path=/health
   ```

   Expect: The answer changes later than before, because your own resolver keeps the old answer until its entry ends.

3. **Repair and reset**: Restore both settings.

   ```bash
   terraform apply -var deploy_traffic_manager=true -var tm_ttl_seconds=30 -var appgw_probe_path=/healthz
   ```

   Expect: Both back to the defaults.

4. **Checkpoint**: Why does Front Door not have this delay? Answer: clients connect to a fixed anycast address and the edge changes origin itself, so there is no cached answer to wait out; only probe time remains.

## Activity 8: Save the evidence, destroy, confirm

**Goal.** Save what you saw, destroy every stage and confirm that the group is gone.

**Exam skill:** Remember that closing a gate destroys its stage, so save evidence first.

1. **Save the evidence**: Do it while the stages exist.

   ```bash
   ./scripts/verify.sh lb > evidence-lb.txt
   ./scripts/verify.sh appgw > evidence-appgw.txt
   ./scripts/verify.sh afd > evidence-afd.txt
   ./scripts/verify.sh tm > evidence-tm.txt
   ```

   Expect: Four text files with the headers and the page content.

2. **Destroy the lab**: Through your approved workflow. If a stage fails on a dependency, set its gate to false first and apply, then destroy.

   ```bash
   terraform destroy
   ```

   Expect: Every object is deleted, including the gateway and the Front Door profile. Billing stops.

3. **Confirm**: A single true or false answer.

   ```bash
   az group exists -n gtc24-rg
   ```

   Expect: `false`.
