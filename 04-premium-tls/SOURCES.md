# Official references and review scope

Reviewed 2026-11-04. Documentation review is not provider initialization, a real plan, service capacity verification or runtime testing. Source URLs can change. Main-branch provider docs are noted where the version-tagged URL could not be fetched; the installed 5.12.0 schema still requires validation.

## Terraform provider and test syntax

- [AzureRM 5.12.0 Linux Web App documentation](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v5.12.0/website/docs/r/linux_web_app.html.markdown): Node24 LTS stack, app command, source restrictions, publishing-auth flags, logs and exported site credentials. State can contain provider-returned credentials even when publishing basic authentication is disabled. The provider ZIP-upload route is deliberately not used.
- [Firewall policy, official provider source](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy.html.markdown): Premium policy, DNS proxy, UAI, certificate-secret identifier, IDPS/TI fields.
- [Firewall policy rule groups, official provider source](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/website/docs/r/firewall_policy_rule_collection_group.html.markdown): application collections, destination URLs/FQDNs and TLS termination.
- [AzureRM Firewall](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall), [Bastion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/bastion_host), [diagnostics](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting): resource argument references. Registry pages require JavaScript in this authoring reader; source-text review and pending actual schema checks are distinguished.
- [Terraform testing](https://developer.hashicorp.com/terraform/language/tests), [mocking](https://developer.hashicorp.com/terraform/language/tests/mocking): supplied plan-only mock tests. No mock or real Terraform plan was executed.

## Firewall mechanics and PKI

- [Premium features](https://learn.microsoft.com/en-us/azure/firewall/premium-features): TLS interception, URL filtering and IDPS behavior.
- [Premium certificates](https://learn.microsoft.com/en-us/azure/firewall/premium-certificates): intermediate CA, public client trust, Key Vault and certificate prerequisites. No certificate/key generation examples are reproduced or executed in this lab.
- [Premium deployment](https://learn.microsoft.com/en-us/azure/firewall/premium-deploy): existing certificate/policy workflow and approved identity linkage context.
- [Rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing): network/application ordering and why no broad network443 rule is present.
- [SNAT private ranges](https://learn.microsoft.com/en-us/azure/firewall/snat-private-range): application-rule proxy/SNAT distinction from private network rules.
- [DNS settings](https://learn.microsoft.com/en-us/azure/firewall/dns-settings): proxy and client DNS alignment.
- [Known issues](https://learn.microsoft.com/en-us/troubleshoot/azure/firewall/firewall-known-issues): customer-signed origin limitations, CA propagation and current region capacity. The cited East US new-deployment row is Standard-specific, not proof about this Premium lab.
- [Azure routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview): effective longest-prefix routing and appliance next hop.
- [Bastion NSGs](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg): dedicated management service rules.
- [Bastion native client](https://learn.microsoft.com/en-us/azure/bastion/connect-vm-native-client-linux): private SSH/tunnel management.

## Controlled origin

- [Node configuration](https://learn.microsoft.com/en-us/azure/app-service/configure-language-nodejs): supported24 LTS, startup/PORT and platform runtime.
- [Run from ZIP](https://learn.microsoft.com/en-us/azure/app-service/deploy-run-package): ZIP root layout, run-from-package, and Python limitation.
- [ZIP deployment](https://learn.microsoft.com/en-us/azure/app-service/deploy-zip): explicit code upload and restart.
- [Disable basic authentication](https://learn.microsoft.com/en-us/azure/app-service/configure-basic-auth-disable): Entra fallback support in modern CLI while basic publishing remains disabled.
- [App Service TLS](https://learn.microsoft.com/en-us/azure/app-service/overview-tls): platform TLS/default hostname and frontend termination.
- [Access restrictions](https://learn.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions): main/SCM source restrictions and deny defaults.
- [Supported Web/sites logs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-web-sites-logs): HTTP, console and IPSec audit categories.

## Evidence schema and client tools

- [AZFWApplicationRule](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwapplicationrule): Action, Rule, IsTlsInspected and client source tuple; no DestinationIp column.
- [AZFWIdpsSignature](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/azfwidpssignature): signature/action evidence independent from application Allow.
- [AppServiceHTTPLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appservicehttplogs): frontend path/status/client-IP fields.
- [AppServiceConsoleLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appserviceconsolelogs): ResultDescription containing fixture observations.
- [AppServiceIPSecAuditLogs](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appserviceipsecauditlogs): CIp, Result, Details and untrusted forwarded-header fields.
- [curl manual](https://curl.se/docs/manpage.html): disabling config with first-option-q, CA isolation, protocol bounds and pinned public keys.
- [OpenSSL3 s_client](https://docs.openssl.org/3.0/man1/openssl-s_client/): explicit hostname/chain verification and CA-path/store isolation.
- [Firewall CLI group](https://learn.microsoft.com/en-us/cli/azure/network/firewall/policy/rule-collection-group): extension dependency and current CLI requirements.
- [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/): region-specific future estimate, not a price quote in this draft.
