# Lab guide: site-to-site and point-to-site VPN design

Run the activities in order from the `terraform` folder. **Every command is designed, not tested**: no `terraform init`, `plan`, `validate` or `apply` and no `az` command was run when this lab was written, only `terraform fmt`. The lab ships no apply script: deploy and destroy through your own approved workflow and read every plan first. Addresses in the expected output are RFC 5737 documentation examples; yours will differ. Check current Microsoft docs for SKU facts, limits, timers, metric names and provider attribute names. The simulated on-premises device is a VM running strongSwan and FRR: package names, configuration syntax and behaviour must also be checked.

## Activity 1: Plan the free baseline and read the GatewaySubnet rules

**Goal.** Create the free network objects, and see why the gateway needs a subnet with a fixed name and no other residents.

**Exam skill:** Know that a VPN gateway lives in a subnet named GatewaySubnet (a /27 or larger is typical) and that all expensive objects sit behind gates.

1. **Prepare the inputs and format the code**: From the `terraform` folder. Copy the example file and set only `subscription_id`. Every gate stays `false`.

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   terraform fmt -check -recursive
   terraform init
   terraform plan -out=baseline.tfplan
   ```

   Expect: The plan adds 4 objects: 1 resource group, 1 VNet and 2 subnets. No gateway, no public IP, no VM. (Designed, not tested.)

2. **Apply the free baseline**: Only through your own approved workflow. The baseline has no hourly cost.

   ```bash
   terraform apply baseline.tfplan
   ```

   Expect: Apply complete. The output `gateway_name` is empty and `gateway_public_ips` is an empty list.

3. **Read the subnets**

   ```bash
   az network vnet subnet list -g vpn26-rg --vnet-name vpn26-hub --query "[].{name:name, prefix:addressPrefix}" -o table
   ```

   Expect: `GatewaySubnet 10.60.255.0/27` and `snet-app 10.60.1.0/24`.

4. **Checkpoint**: Why is a /27 a sensible size, and what else may live in GatewaySubnet? Answer: it holds the gateway instances and room to grow; nothing else may be placed there, and the name must be exactly `GatewaySubnet`. Check current Microsoft docs for sizing with active-active and P2S.

## Activity 2: Create the gateway and the simulated site

**Goal.** Open gate 1 (the VPN gateway) and gate 2 (vm-edge, vm-lan, vm-app) and confirm that the on-premises device boots with strongSwan and FRR.

**Exam skill:** Know what a gateway needs (zone-redundant Standard public IPs for an AZ SKU, GatewaySubnet), how slow it is, and that a Standard public IP is closed to inbound until an NSG allows UDP 500 and 4500.

1. **Open gate 1 and plan**: In `terraform.tfvars` set `deploy_vpn_gateway = true`. Leave `active_active = false` for now; decide this before the first apply, because changing it later can be slow or force a rebuild.

   ```bash
   terraform plan -out=gw.tfplan
   terraform apply gw.tfplan
   ```

   Expect: One Standard public IP and the gateway. Creation often takes 30 to 45 minutes. Output `gateway_public_ips` shows the address.

2. **Open gate 2**: Set `deploy_onprem_sim = true` and paste your public key text into `admin_ssh_public_key`.

   ```bash
   terraform plan -out=site.tfplan
   terraform apply site.tfplan
   ```

   Expect: The simulated VNet, an NSG that allows UDP 500 and 4500 from the gateway, the route table on snet-lan, three NICs and three VMs. Output `edge_public_ip` shows vm-edge's address.

3. **Check the gateway**

   ```bash
   az network vnet-gateway show -g vpn26-rg -n vpn26-vpngw --query "{sku:sku.name, mode:activeActive, bgp:enableBgp, state:provisioningState}" -o table
   ```

   Expect: SKU `VpnGw1AZ`, activeActive `false`, bgp `false`, state `Succeeded`.

4. **Check that vm-edge finished booting**: The boot script installs packages, so wait a few minutes after the VM shows as running.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts "swanctl --list-conns; systemctl is-active strongswan" --query "value[0].message" -o tsv
   ```

   Expect: One connection `azure0` and `active`. No SA yet: the Azure side does not exist until Activity 3.

5. **Checkpoint**: Why does vm-edge need the gateway's public IP at boot, and what is the consequence of changing `active_active` later? Answer: it builds one tunnel per gateway IP, so the number of IPs sets the number of tunnels; changing the mode changes the boot script and replaces vm-edge as well as touching the gateway.

## Activity 3: Bring up a static site-to-site tunnel

**Goal.** Open gate 3 so the local network gateway and the connection exist, and prove the tunnel and the data path with status, SAs and a ping.

**Exam skill:** Read a connection's status, the IPsec SAs on the device, and the effective routes of a VM; know that the local network gateway prefixes become routes in the VNet.

1. **Set the key and open gate 3**: Choose a lab-only pre-shared key of 16 or more characters. It lands in the Terraform state and in the VM's custom data, so never reuse a real key.

   ```bash
   terraform plan -out=s2s.tfplan
   terraform apply s2s.tfplan
   ```

   Expect: A local network gateway with address space 10.70.2.0/24, and a connection `vpn26-conn-onprem` using IKEv2 with default policy.

2. **Read the connection**: It can take a minute or two to turn `Connected`.

   ```bash
   ./scripts/vpn-check.sh status
   ```

   Expect: `Connected`, protocol `IKEv2`, bgp `False`.

3. **Read the SA on the device**

   ```bash
   ./scripts/vpn-check.sh device
   ```

   Expect: An IKE SA `ESTABLISHED` and a child SA `INSTALLED` with traffic selectors 0.0.0.0/0 === 0.0.0.0/0. BGP summary is empty: not configured yet.

4. **Read vm-app's effective routes**

   ```bash
   ./scripts/vpn-check.sh routes
   ```

   Expect: `10.70.2.0/24` with next hop type `VirtualNetworkGateway`, source `VirtualNetworkGateway`, besides `10.60.0.0/16` VnetLocal and `0.0.0.0/0` Internet.

5. **Ping across the tunnel**

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 3 10.60.1.10" --query "value[0].message" -o tsv
   ```

   Expect: Three replies. The request goes vm-lan, then the UDR to vm-edge, then the tunnel.

6. **Checkpoint**: The local network gateway lists only 10.70.2.0/24. What happens to a packet from vm-app to 10.70.0.10? Answer: no route covers it, so it follows 0.0.0.0/0 to the Internet and the site never sees it. Static routes only know what you typed.

## Activity 4: Read the evidence and watch dead peer detection

**Goal.** Generate traffic, read the tunnel metrics, then stop the device and watch the failure being detected and healed.

**Exam skill:** Name the tunnel metrics, the state values of a connection and the DPD timeout; know that detection takes tens of seconds and that a static route does not move traffic.

1. **Generate traffic**

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 200 -i 0.2 10.60.1.10 > /dev/null" --query "value[0].message" -o tsv
   ```

   Expect: Takes about 40 seconds.

2. **Read the metrics**: Metric names are written from documentation knowledge; check the portal list if one is rejected.

   ```bash
   ./scripts/vpn-check.sh metrics
   ```

   Expect: TunnelIngressBytes and TunnelEgressBytes are above zero and growing. The TS mismatch counters are zero.

3. **Stop IKE on the device**: This simulates a crashed on-premises device.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts "systemctl stop strongswan; ip xfrm state flush" --query "value[0].message" -o tsv
   ```

   Expect: No output.

4. **Watch the connection fall**: Poll about every 15 seconds. Detection is not instant.

   ```bash
   ./scripts/vpn-check.sh status
   ```

   Expect: `Connected` for a while, then `NotConnected` or `Connecting` once DPD declares the peer dead (the connection's DPD timeout is 45 seconds by default; check current docs).

5. **Start IKE again and watch it heal**: `start_action = start` makes the device initiate immediately.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts "systemctl start strongswan; sleep 5; swanctl --list-sas | head -5" --query "value[0].message" -o tsv
   ```

   Expect: A new IKE SA and child SA with new SPI values. The connection returns to `Connected`.

6. **Checkpoint**: Which side detects the failure, and how fast? Answer: both sides run DPD. The gateway waits about the DPD timeout (45 s default) before it deletes the SA; the device's `dpd_delay` of 10 s detects a dead Azure side sooner. Check current docs for the gateway's exact behaviour.

## Activity 5: Switch on BGP over APIPA

**Goal.** Turn on BGP with APIPA peer addresses, configure FRR on vm-edge, and read the BGP session and the routes it carries.

**Exam skill:** Know the three pieces that must agree for BGP over APIPA (gateway APIPA address, local network gateway peering address, device address), and read BGP peer status, learned routes and effective routes.

1. **Turn on BGP and APIPA**: In `terraform.tfvars` set `enable_bgp = true` and `use_apipa = true`. Changing the gateway can take a while.

   ```bash
   terraform plan -out=bgp.tfplan
   terraform apply bgp.tfplan
   ```

   Expect: The gateway gets ASN 65010 with APIPA address 169.254.21.1, the local network gateway gets ASN 65020 and peering address 169.254.21.2, and the connection gets BGP enabled.

2. **Configure FRR on vm-edge**: The script adds 169.254.21.2 to the loopback, routes 169.254.21.1/32 into the tunnel, and peers with ASN 65010.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts @scripts/onprem-bgp.sh --query "value[0].message" -o tsv --parameters apipa 65010 65020
   ```

   Expect: `show ip bgp summary` lists neighbor 169.254.21.1 and, after a short wait, state `Established` with one prefix received.

3. **Read the gateway's view**

   ```bash
   ./scripts/vpn-check.sh bgp
   ./scripts/vpn-check.sh learned
   ```

   Expect: Peer 169.254.21.2 `Connected`. Learned routes include 10.70.2.0/24 with origin `EBgp` and ASN path 65020.

4. **Read what Azure advertises**

   ```bash
   ./scripts/vpn-check.sh advertised 169.254.21.2
   ```

   Expect: 10.60.0.0/16 with ASN path 65010.

5. **Read vm-app's effective routes again**

   ```bash
   ./scripts/vpn-check.sh routes
   ```

   Expect: 10.70.2.0/24 now arrives through BGP (state Active). Adding a subnet on the site later needs no change in Azure.

6. **Checkpoint**: Which three values must match for the session to come up? Answer: the APIPA address configured on the gateway instance (169.254.21.1), the on-premises peer address in the local network gateway (169.254.21.2) and the address vm-edge really uses as BGP source, plus matching ASNs (65010 and 65020).

## Activity 6: Apply a custom IPsec policy and measure the packet size

**Goal.** Move the connection from the default policy to one explicit policy, then find the largest packet the tunnel passes and check the MSS clamp.

**Exam skill:** Know that a custom policy replaces the defaults for that connection on both ends, name the parameters, and work out MTU and MSS from the IPsec overhead.

1. **Turn on the custom policy**: Set `custom_ipsec_policy = true`. Terraform sets IKE AES256, SHA256, DH group 14, IPsec AES256, SHA256, PFS14 and the lifetimes on the connection. vm-edge already proposes exactly this.

   ```bash
   terraform plan -out=policy.tfplan
   terraform apply policy.tfplan
   ```

   Expect: The connection is updated in place. The tunnel may renegotiate briefly.

2. **Confirm the new SA**

   ```bash
   ./scripts/vpn-check.sh device
   ```

   Expect: The IKE SA shows AES_CBC_256/HMAC_SHA2_256_128/MODP_2048 and the child SA shows PFS MODP_2048.

3. **Find the largest packet**: ping with the Don't Fragment bit set, from vm-lan to vm-app.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-lan --command-id RunShellScript --scripts @scripts/mtu-test.sh --query "value[0].message" -o tsv --parameters 10.60.1.10 1500
   ```

   Expect: The test steps down from 1500 and prints the largest size that passes, about 1400 or less (it depends on overhead and the tunnel interface MTU of 1400).

4. **Read the clamp**

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts "iptables -t mangle -S FORWARD | grep TCPMSS" --query "value[0].message" -o tsv
   ```

   Expect: A TCPMSS rule with `--set-mss 1350`: the SYN's MSS is lowered so TCP never builds packets that are too big.

5. **Checkpoint**: Why 1350 and not 1460? Answer: 1460 assumes a 1500-byte packet, but IPsec adds an outer IP header, ESP header, IV, padding and ICV, leaving about 1400 for the inner packet. 1350 keeps a safety margin.

## Activity 7: Add point-to-site with certificate authentication

**Goal.** Open gate 4, give the gateway a client address pool and a root certificate, and see which routes a client receives.

**Exam skill:** Know the three P2S protocols and three authentication types, which combinations are valid, how the address pool is chosen, and that a client profile is a snapshot of the routes.

1. **Create a lab root and client certificate**: On your workstation, not in Azure. These are lab-only files: do not reuse them.

   ```bash
   openssl req -x509 -newkey rsa:3072 -nodes -keyout root.key -out root.crt -days 90 -subj "/CN=vpn26-lab-root"
   openssl req -newkey rsa:3072 -nodes -keyout client.key -out client.csr -subj "/CN=vpn26-client"
   openssl x509 -req -in client.csr -CA root.crt -CAkey root.key -CAcreateserial -out client.crt -days 30
   openssl x509 -in root.crt -outform der | base64 -w0
   ```

   Expect: The last command prints the base64 text of the root certificate on one line. Paste it into `p2s_root_cert_public_data`.

2. **Open gate 4**: Set `deploy_p2s = true` and keep `p2s_auth_type = "certificate"`. Entra ID authentication needs `entra_tenant_id` and `entra_audience` instead; check current docs for the audience value.

   ```bash
   terraform plan -out=p2s.tfplan
   terraform apply p2s.tfplan
   ```

   Expect: The gateway is updated in place with pool 172.16.201.0/24, protocols OpenVPN and IkeV2, and one root certificate.

3. **Generate the client profile**: The command prints a URL to a profile package. Download it only with your own approved process.

   ```bash
   az network vnet-gateway vpn-client generate -g vpn26-rg -n vpn26-vpngw --authentication-method EAPTLS
   ```

   Expect: A time-limited URL. The package holds the gateway address, the protocol settings and the routes the client will install.

4. **Connect and read the client's routes**: Use an OpenVPN or IKEv2 client on a workstation that you own; this step cannot be done from the lab VMs.

   ```bash
   ping 10.60.1.10
   ip route | grep 172.16.201
   ```

   Expect: A reply from vm-app. The client has a route for 10.60.0.0/16 into the tunnel and an address from 172.16.201.0/24. With BGP on, the site prefix 10.70.2.0/24 is in the profile too.

5. **Checkpoint**: A peering to another VNet is added tomorrow. Do existing clients reach it? Answer: no, not until they re-download and re-import the profile (or the client re-reads its routes). The profile is a snapshot of the routes at download time.

## Activity 8: Break/fix drills and clean-up

**Goal.** Inject three faults on vm-edge, diagnose each one with the evidence, undo them, and destroy the lab.

**Exam skill:** Diagnose tunnel up but no traffic, a BGP session that never establishes, and an MTU black hole, using status, metrics, BGP peer status, effective routes and packet-size tests.

1. **Drill 1: tunnel up, no traffic**: Narrow the selectors on the device.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts @scripts/onprem-fault.sh --query "value[0].message" -o tsv --parameters ts-narrow
   ```

   Expect: The device reloads its configuration.

2. **Diagnose drill 1**: Ping again from vm-lan and read the evidence before you read the answer.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 3 -W 2 10.60.1.10" --query "value[0].message" -o tsv
   ./scripts/vpn-check.sh status
   ./scripts/vpn-check.sh metrics
   ```

   Expect: No replies, the connection still `Connected`, and the TS mismatch counters grow. Answer: the selectors on the device no longer cover 10.70.2.0/24, so packets from vm-lan match no child SA.

3. **Drill 2: APIPA mismatch**: Make vm-edge use 169.254.21.3 as its BGP source. Needs Activity 5.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts @scripts/onprem-fault.sh --query "value[0].message" -o tsv --parameters apipa-mismatch
   ```

   Expect: FRR now sends from an address the local network gateway does not list.

4. **Diagnose drill 2**

   ```bash
   ./scripts/vpn-check.sh bgp
   ./scripts/vpn-check.sh learned
   ```

   Expect: The peer is not `Connected`, the learned routes are gone, and traffic to 10.70.2.0/24 falls back to Internet. Answer: the peer address vm-edge uses (169.254.21.3) differs from the local network gateway's peering address (169.254.21.2).

5. **Drill 3: MTU black hole**: Drop the ICMP warning and remove the MSS clamp.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts @scripts/onprem-fault.sh --query "value[0].message" -o tsv --parameters mtu-blackhole
   ```

   Expect: The clamp rule is removed and an ICMP rule is added.

6. **Diagnose drill 3**: Small packets pass and big ones do not.

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-lan --command-id RunShellScript --scripts "ping -c 2 10.60.1.10; ping -M do -c 2 -W 2 -s 1472 10.60.1.10" --query "value[0].message" -o tsv
   ```

   Expect: The first ping works, the second (1500 bytes with DF) gets no reply and no ICMP message. Answer: a black hole: the host never learns the path MTU.

7. **Undo the faults**

   ```bash
   az vm run-command invoke -g vpn26-rg -n vm-edge --command-id RunShellScript --scripts @scripts/onprem-fault.sh --query "value[0].message" -o tsv --parameters reset
   ```

   Expect: Traffic, BGP and the MSS clamp return.

8. **Destroy the lab**: Close the gates by destroying, in your own approved workflow. The gateway is the item that costs most.

   ```bash
   terraform plan -destroy -out=destroy.tfplan
   terraform apply destroy.tfplan
   ```

   Expect: Everything Terraform created is deleted. Check the resource group in the portal.
