# Operator evidence record

**Template only. All runtime cases start as NOT RUN.** Replace expected values with observed data; do not infer success from this template.

- Operator / authorized deployment window:
- Actual subscription / region (redact before sharing):
- Deployment time UTC:
- Terraform version / AzureRM version / lock file reviewed:
- Image publisher, offer, SKU and resolved version:
- Policy mode: network / application
- Firewall resource ID / actual private IP F / actual public IP P:
- VM ID / actual private IP:
- Allowed hostnames and observed IPv4 answers:
- Approved echo endpoint or server-side source-IP evidence:

| Case | Status | Observation | Evidence file / UTC correlation |
|---|---|---|---|
| No VM public IP / private workload subnet | NOT RUN | | |
| Two peerings Connected / forwarded traffic | NOT RUN | | |
| Effective default route via actual F | NOT RUN | | |
| Effective NSG supports intended tests | NOT RUN | | |
| Guest uses actual firewall DNS | NOT RUN | | |
| DNS proxy UDP/TCP transport checks, if dig exists | NOT RUN | Leave NOT RUN when dig is absent | |
| Allowed HTTPS origin response + matching Allow | NOT RUN | | |
| Echo public source equals actual P | NOT RUN | | |
| HTTP/TCP80 firewall Deny | NOT RUN | | |
| Unlisted HTTPS hostname observation | NOT RUN | Network-mode shared-IP caveat applies | |
| Direct Azure DNS UDP/TCP probes plus effective NSG | NOT RUN | If skipped, DNS bypass prevention is unverified; no firewall log expected | |
| External UDP443/TCP22 packet-deny tests | NOT RUN | Not implemented by the supplied harness; policy intent only | |
| Optional Network Watcher next-hop | NOT RUN | Needs existing authorized watcher | |
| Cleanup state empty / dedicated RG absent | NOT RUN | | |

Use only PASSED, FAILED, INCONCLUSIVE or NOT RUN. A skipped DNS probe must remain NOT RUN; DNS resolution via the proxy does not prove alternate DNS paths are blocked. For network-mode unlisted-host results, record whether the actual destination IP was also allowed; do not treat a shared-IP allow as failure of SNI filtering, which is not implemented in that mode.

## Issues and limitations

## Cleanup confirmation and retained evidence
