"""Fake Azure/Terraform only; projected status is never network/policy proof."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1];SUB='11111111-1111-1111-1111-111111111111';BASE=f'/subscriptions/{SUB}/resourceGroups/inspection-spp/providers/';NET=BASE+'Microsoft.Network/'
def data():
 v={'deployment_enabled':True,'resource_group_name':'inspection-spp','location':'westeurope','hub_name':'spp-hub','hub_id':NET+'virtualHubs/spp-hub','vwan_id':NET+'virtualWans/lab-wan','connection_id':NET+'virtualHubs/spp-hub/hubVirtualNetworkConnections/connect-app','hub_default_route_table_id':NET+'virtualHubs/spp-hub/hubRouteTables/defaultRouteTable','vpn_gateway_id':NET+'vpnGateways/spp-vpn-gateway','vpn_gateway_name':'spp-vpn-gateway','management_vnet_id':NET+'virtualNetworks/management','spp_id':NET+'securityPartnerProviders/spp-zscaler','origin_public_ips':{'origin1':'20.40.1.10','origin2':'20.40.1.11'},'origin_public_ip_ids':{r:NET+'publicIPAddresses/'+r+'-public-ip' for r in ['origin1','origin2']},'vm_ids':{r:BASE+'Microsoft.Compute/virtualMachines/'+r for r in ['app','origin1','origin2']},'egress_public_ips':['20.40.2.10','20.40.2.11']}
 v['nic_ids']={r:NET+'networkInterfaces/'+r+'-nic' for r in ['app','origin1','origin2']}
 return {k:{'value':v} for k,v in v.items()}
class OperatorTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name);self.bin=self.base/'bin';self.bin.mkdir();self.state=self.base/'state';self.state.write_text(json.dumps(data()));self.out=self.base/'out';self.calls=self.base/'calls'
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'SUBSCRIPTION_ID':SUB,'MOCK_STATE':str(self.state),'MOCK_CALLS':str(self.calls)}
  self.tool('terraform',"import os;print(open(os.environ['MOCK_STATE']).read())")
  self.tool('az',r'''
import json,os,sys
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\n')
if os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')!='no':raise SystemExit(9)
if args[:2]==['extension','show']:
 if os.environ.get('MOCK_MISSING'):raise SystemExit(4)
 print('virtual-wan');raise SystemExit(0)
if '--subscription' not in args:raise SystemExit(8)
if os.environ.get('MOCK_FAIL') and os.environ['MOCK_FAIL'] in ' '.join(args):
 print('synthetic read failure',file=sys.stderr);raise SystemExit(5)
if args[0]=='rest':
 if args[args.index('--method')+1]!='get' or '--query' not in args:raise SystemExit('Unsafe REST request')
 q=args[args.index('--query')+1]
 if any(x in q.lower() for x in ['sharedkey','password','secret']):raise SystemExit('Secret field requested')
 if os.environ.get('MOCK_INVALID'):print('{}');raise SystemExit(0)
 print(json.dumps({'next_link':'https://management.azure.com/next' if os.environ.get('MOCK_PAGINATED') else None,'connections':[] if os.environ.get('MOCK_EMPTY') else [{'id':'mock-connection','connection_status':None,'links':[{'connection_status':None}]}]}));raise SystemExit(0)
if args[:2]==['resource','show']:
 target=args[args.index('--ids')+1]
 if '/vpnGateways/' in target or '/securityPartnerProviders/' in target:
  if '--query' not in args:raise SystemExit('Unsafe raw resource read')
  print(json.dumps({'id':target,'provisioning_state':'Succeeded','connection_status':'Unknown'}));raise SystemExit(0)
print(json.dumps({'mock_only':True,'args':args}))
''')
 def tool(self,name,body):
  p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+body+'\n');p.chmod(0o755)
 def modify(self,key,value):
  v=json.loads(self.state.read_text());v[key]['value']=value;self.state.write_text(json.dumps(v))
 def collect(self,*args,**env):return subprocess.run(['bash',str(R/'scripts/collect-control-plane.sh'),*args,str(self.out)],env={**self.env,**env},capture_output=True,text=True)
 def config(self,role='app',**env):return subprocess.run(['bash',str(R/'scripts/make-runtime-config.sh'),role,str(self.out)],env={**self.env,**env},capture_output=True,text=True)
 def call_list(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
 def test_scoped_projected_readonly_and_unknown_not_healthy(self):
  r=self.collect();self.assertEqual(r.returncode,0,r.stderr)
  for c in self.call_list():
   self.assertFalse(set(c)&{'create','update','delete','apply','deploy','ssh','install','add','post','put'})
   self.assertNotIn('--debug',c)
   if c[:2]!=['extension','show']:self.assertEqual(c[c.index('--subscription')+1],SUB)
  self.assertEqual(json.loads((self.out/'spp-projected.json').read_text())['connection_status'],'Unknown')
  self.assertIn('tunnel_verification=NOT_PERFORMED',(self.out/'summary.txt').read_text());self.assertIn('completed_utc=',(self.out/'timing.txt').read_text());self.assertTrue((self.out/'provider-runtime-evidence-REQUIRED.txt').exists())
  self.assertFalse(any(c[0]=='rest' for c in self.call_list()));self.assertTrue((self.out/'vpn-connections-SKIPPED.txt').exists());self.assertFalse((self.out/'vpn-connections-projected.json').exists());self.assertIn('vpn_connection_read_opted_in=false',(self.out/'summary.txt').read_text())
 def test_explicit_vpn_read_acknowledgement_is_scoped(self):
  result=self.collect('--acknowledge-full-vpn-response');self.assertEqual(result.returncode,0,result.stderr)
  rest=[c for c in self.call_list() if c[0]=='rest'];self.assertEqual(len(rest),1)
  self.assertEqual(rest[0][rest[0].index('--url')+1],'https://management.azure.com'+NET+'vpnGateways/spp-vpn-gateway/vpnConnections?api-version=2025-05-01')
  self.assertIn('links:',rest[0][rest[0].index('--query')+1]);self.assertNotIn('sharedKey',rest[0][rest[0].index('--query')+1])
  self.assertTrue((self.out/'vpn-response-read-ACKNOWLEDGED.txt').exists());self.assertFalse((self.out/'vpn-connections-SKIPPED.txt').exists());self.assertIn('vpn_connection_read_opted_in=true',(self.out/'summary.txt').read_text())
 def test_unknown_flag_does_not_opt_in_or_read_azure(self):
  self.assertNotEqual(self.collect('--include-vpn').returncode,0);self.assertFalse(self.calls.exists());self.assertFalse(self.out.exists())
 def test_vpn_acknowledgement_not_carried_to_next_invocation(self):
  self.assertEqual(self.collect('--acknowledge-full-vpn-response').returncode,0)
  before=len(self.call_list());self.out=self.base/'second';self.assertEqual(self.collect().returncode,0)
  self.assertFalse(any(c[0]=='rest' for c in self.call_list()[before:]));self.assertTrue((self.out/'vpn-connections-SKIPPED.txt').exists())
 def test_missing_nic_map_no_reads(self):
  values=data();del values['nic_ids'];self.state.write_text(json.dumps(values));self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_malformed_or_foreign_nic_map_no_reads(self):
  good=data()['nic_ids']['value'];maps=[None,[],{},dict(good,extra=NET+'networkInterfaces/extra'),{k:v for k,v in good.items() if k!='app'}]
  for role in good:
   for value in [None,123,good[role].replace(SUB,'22222222-2222-2222-2222-222222222222'),good[role].replace('inspection-spp','other-rg'),good[role].replace('networkInterfaces','publicIPAddresses'),good[role]+'-other']:
    maps.append(dict(good,**{role:value}))
  for values in maps:
   with self.subTest(value=values):
    self.modify('nic_ids',values);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_private_evidence_notice_does_not_claim_automatic_redaction(self):
  values=data();values['provider_profile']={'value':{'evidence_reference':'nonsecret-free-text-retained-verbatim'}};self.state.write_text(json.dumps(values))
  result=self.collect();self.assertEqual(result.returncode,0,result.stderr)
  note=(self.out/'PRIVATE-HANDLING-REQUIRED.txt').read_text()
  for token in ['client-side','omitted from Get/List','no PSK receipt is asserted','without redaction','Enter no sensitive data','before sharing']:self.assertIn(token,note)
  self.assertEqual(json.loads((self.out/'terraform-outputs.json').read_text())['provider_profile']['value']['evidence_reference'],'nonsecret-free-text-retained-verbatim')
  self.assertEqual(self.out.stat().st_mode&0o777,0o700);self.assertEqual((self.out/'terraform-outputs.json').stat().st_mode&0o777,0o600)
 def test_invalid_uuid_no_calls(self):self.assertNotEqual(self.collect(SUBSCRIPTION_ID='wrong').returncode,0);self.assertFalse(self.calls.exists())
 def test_other_subscription_no_calls(self):self.assertNotEqual(self.collect(SUBSCRIPTION_ID='22222222-2222-2222-2222-222222222222').returncode,0);self.assertFalse(self.calls.exists())
 def test_foreign_gateway_no_calls(self):self.modify('vpn_gateway_id',NET+'vpnGateways/shared');self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_foreign_spp_no_calls(self):self.modify('spp_id',NET+'networkVirtualAppliances/fake');self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_foreign_vm_no_calls(self):
  ids=data()['vm_ids']['value'];ids['origin2']=BASE+'Microsoft.Compute/virtualMachines/other';self.modify('vm_ids',ids);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_disabled_no_calls(self):self.modify('deployment_enabled',False);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_spp_initially_absent(self):self.modify('spp_id',None);self.assertEqual(self.collect().returncode,0);self.assertTrue((self.out/'spp-NOT-ENABLED.txt').exists());self.assertFalse((self.out/'spp-projected.json').exists())
 def test_omitted_spp_id_is_disabled_no_empty_resource_read(self):
  v=json.loads(self.state.read_text());del v['spp_id'];self.state.write_text(json.dumps(v));result=self.collect();self.assertEqual(result.returncode,0,result.stderr);self.assertNotIn('KeyError',result.stderr);self.assertTrue((self.out/'spp-NOT-ENABLED.txt').exists());self.assertFalse((self.out/'spp-projected.json').exists())
  for c in self.call_list():
   if '--ids' in c:self.assertTrue(c[c.index('--ids')+1])
 def test_missing_required_gateway_still_rejected(self):
  v=json.loads(self.state.read_text());del v['vpn_gateway_id'];self.state.write_text(json.dumps(v));self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_existing_out_refused(self):self.out.mkdir();(self.out/'keep').write_text('old');self.assertNotEqual(self.collect().returncode,0);self.assertEqual((self.out/'keep').read_text(),'old')
 def test_missing_extension_no_resource_reads(self):self.assertNotEqual(self.collect(MOCK_MISSING='1').returncode,0);self.assertFalse(self.out.exists());self.assertTrue(all(c[:2]==['extension','show'] for c in self.call_list()))
 def test_partial_failure_saved_and_continued(self):self.assertEqual(self.collect(MOCK_FAIL='show-effective-route-table').returncode,3);self.assertEqual((self.out/'app-effective-routes.exit').read_text().strip(),'5');self.assertTrue((self.out/'origin2-public-ip.json').exists())
 def test_pagination_incomplete_not_silently_followed(self):self.assertEqual(self.collect('--acknowledge-full-vpn-response',MOCK_PAGINATED='1').returncode,3);self.assertTrue((self.out/'vpn-projection-INCOMPLETE.txt').exists());self.assertEqual(sum(c[0]=='rest' for c in self.call_list()),1)
 def test_invalid_projection_incomplete(self):self.assertEqual(self.collect('--acknowledge-full-vpn-response',MOCK_INVALID='1').returncode,3);self.assertTrue((self.out/'vpn-projection-INCOMPLETE.txt').exists())
 def test_empty_transport_never_verified(self):self.assertEqual(self.collect('--acknowledge-full-vpn-response',MOCK_EMPTY='1').returncode,0);self.assertIn('NOT_PERFORMED',(self.out/'summary.txt').read_text())
 def test_runtime_config_five_fields_local_nonclobber(self):
  result=self.config();self.assertEqual(result.returncode,0,result.stderr);v=json.loads(self.out.read_text());self.assertEqual(len(v),5);self.assertEqual(v['origins']['origin2']['private_ip'],'10.30.1.21');self.assertEqual(self.out.stat().st_mode&0o777,0o600);self.assertFalse(self.calls.exists());self.assertNotEqual(self.config().returncode,0)
 def test_each_origin_role(self):
  for role,ip in [('origin1','10.30.1.20'),('origin2','10.30.1.21')]:
   self.out=self.base/role;self.assertEqual(self.config(role).returncode,0);self.assertEqual(json.loads(self.out.read_text())['private_ip'],ip)
 def test_duplicate_or_reserved_origins_rejected(self):
  for ds in [{'origin1':'20.40.1.10','origin2':'20.40.1.10'},{'origin1':'203.0.113.10','origin2':'20.40.1.11'}]:
   self.modify('origin_public_ips',ds);self.assertNotEqual(self.config().returncode,0);self.assertFalse(self.out.exists())
 def test_invalid_or_oversized_pool_rejected(self):
  for pool in [[],['198.51.100.80'],['224.0.0.1'],['100.64.0.1'],['20.40.1.11'],[f'20.40.2.{i}' for i in range(1,18)]]:
   self.modify('egress_public_ips',pool);self.assertNotEqual(self.config().returncode,0);self.assertFalse(self.out.exists())
if __name__=='__main__':unittest.main()
