# DNS diagnosis checklist (designed, not tested)

Ask in this order. Stop at the first answer that explains the symptom.

1. Which resolver did the client ask? `cat /etc/resolv.conf` and `resolvectl status` on the VM.
   168.63.129.16 means Azure-provided DNS; any other address is a custom DNS server.
2. Ask that resolver and 168.63.129.16 the same question: `python3 /opt/lab/dnsq.py NAME SERVER`.
   Different answers mean the custom server is not forwarding to 168.63.129.16.
3. NXDOMAIN or a public address? NXDOMAIN usually means a linked zone matches but has no record (or no link exists for a
   private-only name). A public address for a Private Link name usually means the zone is not linked to this VNet.
4. Links: `az network private-dns link vnet list -g RG -z ZONE -o table`. Is this VNet listed, and is it Completed?
5. Records: `az network private-dns record-set list -g RG -z ZONE -o table`. Is the record there, with the right IP?
6. TTL: a correct record can still look wrong until the cached copy expires.
7. Check current Microsoft docs for DNS query logging and DNS security policy before you rely on them.
