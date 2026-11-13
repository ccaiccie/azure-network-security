# Primary sources reviewed 4 November 2026

These sources inform the draft, not a claim of loaded provider schema or live TLS/WAF behavior. Source-only reasoning must be checked against the actual approved region, API, provider and deployment.

## Azure design and security

- [Application Gateway forwarding](https://learn.microsoft.com/en-us/azure/application-gateway/how-application-gateway-works): independent proxy connections and the public versus private backend source distinction. This lab uses a public backend and frontend P as its source.
- [Gateway infrastructure requirements](https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure): dedicated subnet, platform traffic, GatewayManager/AzureLoadBalancer and unrestricted required outbound access for conventional public WAF_v2. No hidden instance NIC effective-route claim.
- [Front Door origin protection](https://learn.microsoft.com/en-us/azure/frontdoor/origin-security): source service tag and exact profile identity together. A public FDID header alone is not a network boundary.
- [Gateway custom WAF rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview): Any/Regex conditions and custom Allow/Block processing. The draft uses only custom Block actions. Missing/duplicate actual behavior still needs runtime acceptance evidence.
- [Front Door end-to-end TLS](https://learn.microsoft.com/en-us/azure/frontdoor/end-to-end-tls): distinct TLS sessions, public origin trust and hostname checks. No disabled name verification or self-signed shortcut.
- [Gateway Key Vault certificates](https://learn.microsoft.com/en-us/azure/application-gateway/key-vault-certs): existing identity, certificate format/access/network prerequisites and versionless reference lifecycle. No secret value is read during this work.
- [Gateway TLS](https://learn.microsoft.com/en-us/azure/application-gateway/ssl-overview): the listener needs a separately provisioned certificate; the module cannot issue one.
- [Front Door headers](https://learn.microsoft.com/en-us/azure/frontdoor/front-door-http-headers-protocol): socket/client/forwarded attribution are different. The lab does not authenticate arbitrary forwarded headers.
- [Front Door probes](https://learn.microsoft.com/en-us/azure/frontdoor/health-probes): probe behavior is distinct from user traffic, including all-unhealthy forwarding. Health is never used as an isolation control.
- [Gateway probes](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-probe-overview): explicit backend HTTPS host/path/status and separate probe identity. A healthy configuration alone does not prove a specific user request.
- [App Service access restrictions](https://learn.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions): independent main-site/SCM rules and unmatched Deny.
- [App Service deployment with basic authentication disabled](https://learn.microsoft.com/en-us/azure/app-service/configure-basic-auth-disable): approved current CLI/Entra workflow rather than retrieving publishing passwords.
- [Deploy a ZIP package](https://learn.microsoft.com/en-us/azure/app-service/deploy-zip): reviewed artifact upload; the supplied helper snapshots already-reviewed bytes and never rebuilds before upload.
- [Front Door Premium to Application Gateway Private Link](https://learn.microsoft.com/en-us/azure/frontdoor/how-to-enable-private-link-application-gateway): currently supported capability, but not implemented or silently inferred by this public-origin baseline.
- [Pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/): future region/subscription budget review; no price quote was retrieved here.

## Provider scope

The root pins AzureRM 5.12.0 and Terraform >=1.9,<2. No executable/schema/cache was installed or loaded, and no lock file is fabricated.

Fetched pinned references:
- [Linux Web App 5.12](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/linux_web_app.html.markdown): Node24, restrictions and exported site credentials. Basic-auth disablement does not make provider state free of credentials.
- [Log Analytics workspace 5.12](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/log_analytics_workspace.html.markdown): `local_authentication_enabled=false`, and exported primary/secondary shared keys.
- [Diagnostic settings 5.12](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/monitor_diagnostic_setting.html.markdown): enabled_log/enabled_metric and resource-specific destination support; actual category availability still must be checked.

Pinned gateway, regional/edge WAF and Front Door route document fetches returned cache misses. Current official references informed the draft, without proving pinned compatibility:
- [Application Gateway](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/application_gateway.html.markdown).
- [Regional WAF policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/web_application_firewall_policy.html.markdown).
- [Front Door WAF policy](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/cdn_frontdoor_firewall_policy.html.markdown).
- [Front Door origin](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/cdn_frontdoor_origin.html.markdown).

## Observation schemas

- [AGWAccessLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/agwaccesslogs): immediate client, proxy/backend TLS and request correlation fields. Never substitute original C for the gateway's observed immediate Front Door peer.
- [AGWFirewallLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/agwfirewalllogs): named rule/action/policy/transaction. A status response alone is not equivalent evidence.
- [Front Door monitoring reference](https://learn.microsoft.com/en-us/azure/frontdoor/monitor-front-door-reference): Premium profile categories/metrics rather than Classic-only assumptions. Actual AzureDiagnostics fields must be inspected; missing dynamic fields remain inconclusive.
- [AppServiceIPSecAuditLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appserviceipsecauditlogs): frontend client/address restriction outcome, not Node's internal socket or user-supplied forwarded identity.
- [AppServiceHTTPLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appservicehttplogs): case User-Agent/request and response observations.

No certificate issuance, real handshake, WAF request, Key Vault read, DNS mutation, API response or deployment was performed to validate these claims. The helper's mock trust checks verify control flow/configuration only.
