# Scenario11 actual-results worksheet

**All Azure/provider/guest/packet outcomes start NOT RUN.** Offline mocks are separate. Keep this worksheet, metadata, diagnostics, PCAPs and body prefixes private. Use synthetic traffic, review/redact an approved copy before sharing; no automatic upload.

## Approved setup and identity

- Approved subscription, region/GWLB eligibility, cost/image/tool authorization: NOT RUN
- Exact immutable image, kernel/bridge/nft/VXLAN/tcpdump and MTU prerequisites: NOT RUN
- Genuine provider lock/schema/fmt/validate/mock plans/rendered custom-data: NOT RUN
- Exact Gateway/consumer/frontend/pool/probe/NIC/VM/publicIP resource IDs: NOT RUN
- Actual global C/P, external local source and separate NAT mapping C:c: NOT RUN
- Management-only peering/Bastion reachability, no public VM/UDR/NAT/outbound bypass: NOT RUN

## Local readiness versus platform observations

- Both NVA ownership/original MTU records, non-addressed owned bridge/tunnels, exact VNIs/UDP ports: NOT RUN
- Underlay1550/inner1500 and active bridge ports, primaryNIC outside bridge: NOT RUN
- Exact bridge-family table/mode/digest/named counters, unrelated policy retained: NOT RUN
- Guest L2 checks versus Azure NIC forwarding; no global ip_forward/rp_filter change assumed: NOT RUN
- Local fresh NVA8008 readiness/advertisement and Azure per-instance probe history: NOT RUN
- Both backend8080/8081 listeners, independent8009 readiness and app probe history: NOT RUN
- Actual exact appNSG C/32 envelope plus outer provider envelope/effective routes: NOT RUN
- Actual consumer frontend chain resource reference and no alternate path: NOT RUN

## Per-attempt tuple ledger

Record UTC start/end, local/client-NAT original tuple, case ID when delivered, selected NVA, both outer UDP addresses/ports and VNI, observed inner Ethernet/IP/TCP at each tunnel, B socket/journal and public response. Mark unknown stages explicitly; the inner candidate union is not observed translation.

| Case | Required proof | Status |
|---|---|---|
| Closed8080 | Exact NSG open, app ready, incoming capture and named primaryDeny counter on selected NVA | NOT RUN |
| Primary8080 | Acknowledged persistent narrow Allow, actual chain, both-direction same-NVA capture and matching backend fixture | NOT RUN |
| Alternate8081 | Independently healthy listener, selected-NVA named8081Deny with fresh tuple/time | NOT RUN |
| Large payload | Exact size/hash plus separate MTU/MSS/fragmentation evidence; not PMTU proof from bytes alone | NOT RUN |
| Close old/new | Held stream timeline, actual close event, new attempted tuple, ended flows separately | NOT RUN |
| One-node health withdrawal | Identified old owner, other healthy, bounded event and actual new-flow owner/probe histories | NOT RUN |
| Safe restoration | Actual helper exit/pending/uncertain outcome, local checks and Azure health, no assumed seamless recovery | NOT RUN |

Empty inner captures can reflect an unexpected tuple excluded by their filters. Decode bounded outer VXLAN headers and inspect capture exit/stderr before conclusions. Probe health, aggregate metrics, HTTP200, timeout or fixture identity alone is not path/policy proof.

## Recovery and cleanup

- Persistent operations/events/snapshots and pending/uncertain records reviewed: NOT RUN
- Exact helper exited/lock free before another mutation; no lock-file deletion: NOT RUN
- Reconcile/recover safe closed+withdrawn; reopening explicitly reviewed: NOT RUN
- Client attempts stopped, both bridge policies closed, app units inactive and successful ss empty: NOT RUN
- Exact NSG Deny and existing-flow termination verified before chain removal: NOT RUN
- Consumer chain detached only after isolation; no public bypass interval assumed safe: NOT RUN
- Owned devices/table removed and only original underlayMTU restored: NOT RUN
- Owned cloud resources/residual billing removed with management retained until safe: NOT RUN
- Existing image/SSH keys/unrelated resources preserved; approved evidence/state retention: NOT RUN
