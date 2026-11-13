# Lab guide: ExpressRoute multi-region peering and routing

Run the activities in order from the `terraform` folder. **Designed, not tested:** nothing here was ever applied, and every command is a procedure for a future run you decide to make. There is no simulated on-premises router; the steering activities are run on your own router against a real or provider test circuit. ExpressRoute gateways and circuits cost money, so every gate defaults to false and you destroy what you create. All addresses and ASNs are examples.

## Activity 1: Read the code and plan with every gate closed

**Goal.** Understand what each file builds and prove that, with all gates false, the plan creates nothing.

**Exam skill.** Know which resources cost money and which gate controls each.

1. **Format and read**: From the `terraform` folder. Designed, not tested.

   ```bash
   terraform fmt -check -recursive
   grep -n 'default' variables.tf
   ```

   Expect: No formatting changes; every gate shows `default = false`.

2. **Initialise and plan with gates closed**: Copy `terraform.tfvars.example` to a private file and fill in your subscription ID only.

   ```bash
   terraform init
   terraform plan -var-file="$TFVARS"
   ```

   Expect: Plan: 0 to add. If anything is planned, a gate default was changed.

## Activity 2: Deploy hubs, spokes and gateways

**Goal.** Build the two-region base and, if you accept the cost, the two zone-redundant ExpressRoute gateways.

**Exam skill.** Know the GatewaySubnet rules and which peering flags let a spoke use the hub's gateway.

1. **Hubs and spokes first**: Choose two regions in your own subscription. Designed, not tested.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var deploy_lab=true
   ```

   Expect: Two hubs, two spokes, GatewaySubnets and hub-to-spoke peerings; no gateway yet.

2. **Add the gateways**: This stage bills by the hour and takes a long time. Review the plan before you apply.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var deploy_lab=true -var deploy_er_gateways=true
   ```

   Expect: Two ExpressRoute gateways, each with a Standard public IP. Provisioning commonly takes 30 to 45 minutes or more.

3. **Look at the effective routes of a spoke VM (optional)**: Needs `deploy_test_vms`. Replace names with your outputs.

   ```bash
   az network nic show-effective-route-table \
     -g "$RG" -n "$NIC_A" -o table
   ```

   Expect: VnetLocal and VNetPeering routes only; no on-premises prefix yet.

## Activity 3: Create the circuits and give the service keys to a provider

**Goal.** Create two circuit resources, hand each service key to the provider, and wait for provisioning, which happens outside Terraform.

**Exam skill.** Know that the service key and the provider provision the circuit, and what states mean.

1. **Create the circuits**: Fill `circuits` in your tfvars first. Circuits bill from creation. Designed, not tested.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var deploy_lab=true -var create_circuits=true
   ```

   Expect: Two circuits in the state NotProvisioned.

2. **Read the service keys (do not paste them anywhere public)**: The keys are sensitive outputs.

   ```bash
   terraform output -json circuit_service_keys
   ```

   Expect: Two keys. Send each to the provider through the provider's own process.

3. **Wait for the provider**: Poll the state. This can take days or weeks with a real provider.

   ```bash
   az network express-route show -g "$RG" -n "$CIRCUIT_A" \
     --query "{provider:serviceProviderProvisioningState,circuit:circuitProvisioningState}"
   ```

   Expect: provider: Provisioned when the provider has finished.

4. **Private peering (only if you configure it)**: Many providers configure peering for you. If you do it yourself, set the example /30s, VLAN and your private ASN in tfvars first.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var create_circuits=true \
     -var configure_private_peering=true
   ```

   Expect: Private peering created on each circuit; BGP comes up when your router is configured with the same values.

## Activity 4: Create the connections and read the routes

**Goal.** Connect each gateway to both circuits with weights, then read the routes on the circuit, the gateway and a VM.

**Exam skill.** Read advertised, learned and effective routes for one prefix in three places.

1. **Create the four connections**: Weights default to 100 for the local circuit and 0 for the other. Designed, not tested.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var create_connections=true
   ```

   Expect: hubA-circA, hubA-circB, hubB-circB, hubB-circA, with the weights in `connection_weights`.

2. **Circuit route table and ARP**: Run for each circuit and each path (primary, secondary).

   ```bash
   az network express-route list-arp-tables -g "$RG" -n "$CIRCUIT_A" \
     --peering-name AzurePrivatePeering --path primary -o table
   az network express-route list-route-tables -g "$RG" -n "$CIRCUIT_A" \
     --peering-name AzurePrivatePeering --path primary -o table
   ```

   Expect: An ARP entry for your router's /30 address and routes that include 192.168.10.0/24 and the VNet prefixes.

3. **Gateway learned and advertised routes**: Gateway name from the output. The peer address is your router's /30 address.

   ```bash
   az network vnet-gateway list-learned-routes -g "$RG" -n "$GW_A" -o table
   az network vnet-gateway list-advertised-routes -g "$RG" -n "$GW_A" \
     --peer 172.31.255.1 -o table
   ```

   Expect: 192.168.10.0/24 learned twice (one per circuit), and the VNet prefixes advertised.

4. **Effective routes of the VM**: Needs `deploy_test_vms`.

   ```bash
   az network nic show-effective-route-table \
     -g "$RG" -n "$NIC_A" -o table
   ```

   Expect: 192.168.10.0/24 with next hop type VirtualNetworkGateway.

## Activity 5: Steer on-premises to Azure with local preference

**Goal.** Prefer circuit A for region A prefixes and circuit B for region B prefixes, then prove it. You run this on your own router against a real or provider test circuit.

**Exam skill.** Know that local preference lives on your router and steers only your outbound traffic.

1. **Set local preference on import (pseudo-configuration)**: Vendor-neutral pseudo-configuration; translate it to your router's syntax. Designed, not tested.

   ```bash
   # on CE1, neighbours 172.31.255.2 and .6
   route-map FROM-MSEE-A permit 10
     match prefix-list REGION-A     # 10.1.0.0/16 10.11.0.0/16
     set local-preference 200
   route-map FROM-MSEE-A permit 20
     set local-preference 100
   # on CE2: mirror it with REGION-B
   ```

   Expect: Region A prefixes show 200 on CE1 and region B prefixes show 200 on CE2.

2. **Read your BGP table**: Use your router's command for the BGP table of 10.11.0.0/16.

   ```bash
   show ip bgp 10.11.0.0/16     # vendor syntax varies
   ```

   Expect: The circuit A path is best with local preference 200; the circuit B path is listed with 100.

3. **Check the circuit view of the same prefix**: Compare with what Azure shows.

   ```bash
   az network express-route list-route-tables -g "$RG" -n "$CIRCUIT_A" \
     --peering-name AzurePrivatePeering --path primary -o table
   ```

   Expect: The prefixes you advertised are present; local preference is not visible there, because it never leaves your router.

## Activity 6: Steer Azure to on-premises with weight and prepend, then fail over

**Goal.** Change the weight in Terraform, change the prepend on your router, read the learned routes after each change, and finally take one circuit down. You run the router parts against a real or provider test circuit.

**Exam skill.** Know that weight is compared before AS-path length, and that a one-sided change creates asymmetry.

1. **Equalise the weights**: Edit `connection_weights` in your tfvars so every value is 0, then apply. Designed, not tested.

   ```bash
   terraform apply -var-file="$TFVARS" \
     -var create_connections=true
   ```

   Expect: The weights on the four connections are all 0. Optionally confirm with `az network vpn-connection show --query routingWeight`.

2. **Prepend on circuit A (pseudo-configuration)**: On CE1's export toward circuit A.

   ```bash
   route-map TO-MSEE-A permit 10
     match prefix-list SITE1        # 192.168.10.0/24
     set as-path prepend 65001 65001
   ```

   Expect: CE1 advertises the prefix with a longer path on circuit A.

3. **Read the gateway's learned routes**: Wait for BGP to converge.

   ```bash
   az network vnet-gateway list-learned-routes -g "$RG" -n "$GW_A" -o table
   ```

   Expect: The circuit A path is longer; the gateway now prefers the circuit B path for 192.168.10.0/24. Local preference on your router did not change, so the reply path and the request path now differ.

4. **Restore symmetry, then test a failure**: Set the weights back to 100 and 0 and remove the prepend. Then shut down the sessions of circuit A on CE1 and watch the other circuit take over; keep a ping running from an on-premises host to the VM, with ICMP allowed on the VM's NSG.

   ```bash
   ping -i 0.2 10.11.1.10     # from the host, keep it running
   # on CE1: administratively shut down both neighbours of circuit A
   ```

   Expect: Packet loss for the convergence time, then replies resume over circuit B. Note the measured time; it depends on BGP timers and BFD. Re-enable the sessions and watch failback.
