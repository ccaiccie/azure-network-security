# Scenario 13 runtime evidence worksheet

**All Azure, guest/kernel, provider and end-to-end rows are NOT RUN.** Do not replace these fields with local mock output. The only observed results in this draft are local source/guarded-loopback/mock tests recorded in validation/STATUS.md.

Record operator authorization reference, actual subscription/RG/region, image version and approved image baseline, provider/lock hashes, source hash, source_mode, all gate values, private evidence directory, UTC start/end and the current cost/cleanup owner. Never include private keys, credentials, workspace keys or real customer payload. F/P/D below must be actual observed addresses, not example placeholders.

| Evidence item | Status | Private evidence/reference |
|---|---|---|
| Approved image tools and preloaded nf_conntrack sysctl at clean boot | NOT RUN | |
| Terraform fmt/schema/mock-provider plans | NOT RUN | |
| Actual Azure deployment/resources and private management access | NOT RUN | |
| Local A readiness and B healthy8080/8081/8082 | NOT RUN | |
| E boot closed policy, owned sysctls and exact interface | NOT RUN | |
| Actual A effective default→F and source subnet NSG | NOT RUN | |
| Firewall data table/default→E; independent management subnet | NOT RUN | |
| E effective Internet default, A return→F and S return hub route | NOT RUN | |
| Independent management paths and no unexpected route/peer/NAT | NOT RUN | |
| Exact current Firewall groups/collections/actions and source-mode ranges | NOT RUN | |
| Exact current NSG envelopes P/D/source mode | NOT RUN | |
| Firewall-closed8080: healthy fixture plus named Azure Deny | NOT RUN | |
| Guest-closed8080: Azure Allow plus guest named closed counter | NOT RUN | |
| First finite8080 positive and broad-enough D/ports capture | NOT RUN | |
| First positive closed/reviewed before broader reopening | NOT RUN | |
| Preserve tuple A:a→D:d at E; conntrack private E:e; B observed P:p | NOT RUN | |
|8081 named Azure Deny with healthy alternate fixture | NOT RUN | |
|8082 Azure Allow plus guest named drop with healthy fixture | NOT RUN | |
| Long-lived single socket; bounded failure UTC; old-flow and fresh-flow outcomes | NOT RUN | |
| Normal recovery and handled interruption behavior | NOT RUN | |
| Optional isolated firewall_private replacement and observed S:s | NOT RUN | |
| Current closure: clients stopped, guest drop, Firewall Deny, NSGs closed, listeners absent | NOT RUN | |
| Final authorized cleanup and cost-bearing resource absence | NOT RUN | |

Per-case fields: case_id; mode; attempted_local IP/port; attempted_destination IP/port; started_utc/completed_utc; TCP/request status; Azure Action/RuleCollectionGroup/RuleCollection/Rule and tuple; perimeter incoming source/port, outgoing private E/port, reverse tuple, named counter before/after and conntrack entry; actual origin peer P/port plus B/listener port; fixture marker and matching case only when HTTP was actually sent; packet/log/source references; conclusion with missing/contradictory evidence.

For a denied SYN, HTTP case ID is absent on the wire. Correlate tuple/time rather than inventing an application log. A missing origin record, empty log query, unsupported read, stale counter or timeout is inconclusive alone. Record skipped tests as skipped, never passed. Logs may be delayed. Transient old-flow survival or failure does not establish state synchronization, HA, VPN transport or FastPath behavior. Record a failed control command as uncertain even if surviving local files appear stable; review current policy and reconcile before reopening.
