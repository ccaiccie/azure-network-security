#!/usr/bin/env python3
"""Selected source assertions, not a HCL parser/provider/runtime validator."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[1];n=0
def N(t):
 return re.sub(r'[ \t]+',' ',t)  # terraform fmt aligns '=' with extra spaces; compare with whitespace runs collapsed
def check(v,msg):
 global n
 assert v,msg
 n+=1
def has(path,*parts):
 s=N((R/path).read_text())
 for p in parts:check(N(p) in s,f'{path}: {p}')
 return s
files=list(R.glob('*.tf'))+list((R/'module').glob('*.tf'))+list((R/'tests').glob('*.tftest.hcl'))
for p in files:
 s=p.read_text();check(not re.search(r'=\s+=',s),str(p)+' equality')
 clean=re.sub(r'"(?:\\.|[^"\\])*"|#[^\n]*|//[^\n]*','',s);stack=[]
 for c in clean:
  if c in '{[(':stack.append(c)
  elif c in '}])':assert stack and stack.pop()=={'}':'{',']':'[',')':'('}[c],str(p)
 check(not stack,str(p)+' balanced delimiters')
v=has('variables.tf','var.certificate_access_confirmed','!var.edge_route_enabled && !var.fdid_diagnostic_ingress_enabled','var.diagnostic_ingress_authorized','var.fdid_negative_cases_verified','!var.fdid_diagnostic_ingress_enabled && !var.fixture_publish_enabled')
check(v==N((R/'module/variables.tf').read_text()),'root/module validation parity')
for g in ['deploy_lab','certificate_access_confirmed','origin_dns_verified','fixture_publish_enabled','fixture_ready','backend_access_enabled','backend_health_verified','gateway_ingress_enabled','fdid_diagnostic_ingress_enabled','diagnostic_ingress_authorized','fdid_negative_cases_verified','edge_route_enabled']:
 b=v.split(f'variable "{g}" {{')[1].split('\nvariable ',1)[0];check('default = false' in b and 'nullable = false' in b,'safe gate '+g)
has('module/main.tf','["10.60.0.0/16"]','["10.60.1.0/24"]','sku = "Standard"','allocation_method = "Static"')
has('module/security.tf','source_address_prefix = "AzureFrontDoor.Backend"','source_address_prefix = var.operator_cidr','priority = 100','priority = 110','priority = 200','priority = 210','priority = 4000','"65200-65535"','"GatewayManager"','"AzureLoadBalancer"')
association=(R/'module/security.tf').read_text().split('resource "azurerm_subnet_network_security_group_association" "gateway"')[1]
check(all('azurerm_network_security_rule.'+name in association for name in ['frontdoor','diagnostic','manager','platform_probe','deny_inbound']),'associate only after all required NSG rules exist')
waf=has('module/waf.tf','"BlockOtherSockets"','"SocketAddr"','"BlockEdgeMarker"','"BlockMissingFDID"','operator = "Any"','"BlockWrongFDID"','operator = "Regex"','"BlockRegionalMarker"','"Microsoft_DefaultRuleSet"','"2.1"','"OWASP"','"3.2"')
check(waf.count('mode = "Prevention"')==2,'two Prevention policies');check('action = "Allow"' not in waf,'no custom Allow bypass')
has('module/gateway.tf','"WAF_v2"','capacity = 2','key_vault_secret_id = var.listener_key_vault_secret_id','identity_ids = [var.gateway_identity_id]','require_sni = true','firewall_policy_id = azurerm_web_application_firewall_policy.gateway.id','host_name = azurerm_linux_web_app.backend.default_hostname','protocol = "Https"','path = "/health"','status_code = ["200"]')
has('module/frontdoor.tf','"Premium_AzureFrontDoor"','certificate_name_check_enabled = true','forwarding_protocol = "HttpsOnly"','request_type = "HEAD"','enabled = var.edge_route_enabled','depends_on = [azurerm_cdn_frontdoor_security_policy.edge]')
check('cache {' not in (R/'module/frontdoor.tf').read_text(),'cache disabled')
has('module/backend.tf','ip_restriction_default_action = "Deny"','scm_ip_restriction_default_action = "Deny"','scm_use_main_ip_restriction = false','for_each = var.fixture_publish_enabled ? [1] : []','for_each = var.backend_access_enabled ? [1] : []','"${azurerm_public_ip.gateway.ip_address}/32"','ftp_publish_basic_authentication_enabled = false','webdeploy_publish_basic_authentication_enabled = false','"24-lts"','SCM_DO_BUILD_DURING_DEPLOYMENT = "false"')
has('module/diagnostics.tf','local_authentication_enabled = false','"AppServiceIPSecAuditLogs"','"ApplicationGatewayFirewallLog"','"FrontDoorWebApplicationFirewallLog"')
alltf='\n'.join(p.read_text() for p in (R/'module').glob('*.tf'))
resources={f'{a}.{b}' for a,b in re.findall(r'resource\s+"([^"]+)"\s+"([^"]+)"',alltf)};refs=set(re.findall(r'\b(azurerm_[a-z0-9_]+\.[a-z0-9_]+)\b',alltf));check(not refs-resources,'no dangling resource references')
for absent in ['resource "azurerm_route_table"','resource "azurerm_role_assignment"','resource "azurerm_user_assigned_identity"','resource "azurerm_key_vault_secret"','data "azurerm_key_vault_secret"','resource "tls_private_key"','resource "azurerm_virtual_machine"','private_link {','filebase64(']:check(absent not in alltf,'excluded '+absent)
has('guest/probe.py','conn.auto_open=0','skip_host=True','CERT_REQUIRED','check_hostname','cadata=ca_pem','ca_bundle_sha256','deadline(20)','settimeout(5)','read(8193)',"write_json(out/'attempt.json'","'waf_block_proven':False","'three_tls_legs_proven':False","'completed_utc'",'fdid-duplicate-valid','fdid-case')
has('scripts/deploy-origin.sh','io.BytesIO(b)','REVIEWED_SHA256','publication_enabled','--subscription "$SUBSCRIPTION_ID"','--src-path "$SNAPSHOT/origin.zip"')
has('scripts/common.sh','Invalid subscription UUID','Wrong scoped','Invalid backend name','Malformed gate map','--subscription "$SUBSCRIPTION_ID"')
has('scripts/collect-control-plane.sh','PRIVATE-HANDLING-REQUIRED.txt','client-side','completed-utc.txt','runtime_path_waf_verification=NOT_PERFORMED')
print(f'PASS {n} selected source assertions. No HCL semantics, provider schema, real TLS/WAF or Azure verification.')
