"""Only fake Terraform/Azure CLI and local JSON comparisons. No cloud traffic."""
import importlib.util,json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SUB='11111111-1111-1111-1111-111111111111'
ARM=f'/subscriptions/{SUB}/resourceGroups/inspection-partner/providers/Microsoft.Network/'
spec=importlib.util.spec_from_file_location('identity',ROOT/'scripts/validate-vendor-identity.py');identity=importlib.util.module_from_spec(spec);spec.loader.exec_module(identity)
PROFILE=json.loads((ROOT/'tests/mock-profile.json').read_text())
def data():
 v={'deployment_enabled':True,'resource_group_name':'inspection-partner','hub_name':'partner-hub','location':'westeurope','hub_id':ARM+'virtualHubs/partner-hub','vwan_id':ARM+'virtualWans/lab-wan','connection_id':ARM+'virtualHubs/partner-hub/hubVirtualNetworkConnections/connect-app','hub_default_route_table_id':ARM+'virtualHubs/partner-hub/hubRouteTables/defaultRouteTable','routing_intent_id':ARM+'virtualHubs/partner-hub/routingIntent/internet-inspection','origin_public_ip_id':ARM+'publicIPAddresses/origin-public-ip','management_vnet_id':ARM+'virtualNetworks/management','origin_public_ip':'20.40.1.10','egress_public_ips':['20.40.2.10','20.40.2.11'],'vendor_profile':PROFILE,'nva_resource_id':PROFILE['nva_resource_id']}
 v.update({role+'_vm_id':f'/subscriptions/{SUB}/resourceGroups/inspection-partner/providers/Microsoft.Compute/virtualMachines/{role}' for role in ('app','origin')})
 v['nic_ids']={role:ARM+'networkInterfaces/'+role+'-nic' for role in ('app','origin')}
 return {k:{'value':v} for k,v in v.items()}
def projected():
 return ({'id':PROFILE['nva_resource_id'],'type':'Microsoft.Network/networkVirtualAppliances','location':'westeurope','provisioning_state':'Succeeded','hub_id':PROFILE['hub_resource_id'],'vendor':PROFILE['nva_vendor'],'marketplace_version':PROFILE['marketplace_version'],'scale_unit':PROFILE['scale_unit']},{'id':PROFILE['managed_application_id'],'type':'Microsoft.Solutions/applications','provisioning_state':'Succeeded','managed_resource_group_id':PROFILE['managed_resource_group_id'],'publisher':PROFILE['marketplace_publisher'],'product':PROFILE['marketplace_offer'],'plan_name':PROFILE['marketplace_plan']})
class IdentityTests(unittest.TestCase):
 def test_matching_metadata_not_policy_proof(self):
  result=identity.verify(data(),*projected());self.assertEqual(result['identity_comparison'],'MATCH');self.assertEqual(result['vendor_compatibility_license_health_policy_snat_routes'],'NOT_VERIFIED')
 def test_every_required_projection_field_mismatch_rejected(self):
  for pos,base in enumerate(projected()):
   for key in base:
    with self.subTest(part=pos,key=key):
     pair=list(projected());pair[pos][key]='wrong';self.assertEqual(identity.verify(data(),*pair)['identity_comparison'],'MISMATCH')
 def test_empty_response_inconclusive_not_match(self):self.assertEqual(identity.verify(data(),{}, {})['identity_comparison'],'MISMATCH')
class OperatorTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name);self.bin=self.base/'bin';self.bin.mkdir();self.out=self.base/'evidence';self.state=self.base/'state';self.state.write_text(json.dumps(data()));self.calls=self.base/'calls'
  nva,app=projected();(self.base/'nva').write_text(json.dumps(nva));(self.base/'app').write_text(json.dumps(app))
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'SUBSCRIPTION_ID':SUB,'MOCK_STATE':str(self.state),'MOCK_CALLS':str(self.calls),'MOCK_BASE':str(self.base)}
  self.tool('terraform',"import os;print(open(os.environ['MOCK_STATE']).read())")
  self.tool('az',r'''
import json,os,sys
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\n')
if os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')!='no':raise SystemExit(9)
if args[:2]==['extension','show']:
 if os.environ.get('MOCK_MISSING_EXT'):raise SystemExit(4)
 print('virtual-wan');raise SystemExit(0)
if '--subscription' not in args:raise SystemExit(8)
if os.environ.get('MOCK_FAIL') and os.environ['MOCK_FAIL'] in ' '.join(args):
 print('synthetic scoped read failure',file=sys.stderr);raise SystemExit(5)
if os.environ.get('MOCK_EMPTY'):print('{}');raise SystemExit(0)
if args[:2]==['resource','show']:
 target=args[args.index('--ids')+1]
 if '/networkVirtualAppliances/' in target or '/Microsoft.Solutions/applications/' in target:
  if '--query' not in args:raise SystemExit('UNPROJECTED SECRET-PRONE RESOURCE READ FORBIDDEN')
  q=args[args.index('--query')+1]
  if any(x in q for x in ['cloudInit','bootStrap','parameters','outputs']):raise SystemExit('UNSAFE PROJECTION')
  print(open(os.environ['MOCK_BASE']+('/nva' if '/networkVirtualAppliances/' in target else '/app')).read());raise SystemExit(0)
print(json.dumps({'mock_only':True,'args':args}))
''')
 def tool(self,name,body):
  p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+body+'\n');p.chmod(0o755)
 def run_collector(self,**env):return subprocess.run(['bash',str(ROOT/'scripts/collect-control-plane.sh'),str(self.out)],env={**self.env,**env},capture_output=True,text=True)
 def run_config(self,role='app',**env):return subprocess.run(['bash',str(ROOT/'scripts/make-runtime-config.sh'),role,str(self.out)],env={**self.env,**env},capture_output=True,text=True)
 def modify(self,key,value):
  v=json.loads(self.state.read_text());v[key]['value']=value;self.state.write_text(json.dumps(v))
 def call_list(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
 def test_scoped_projected_readonly(self):
  r=self.run_collector();self.assertEqual(r.returncode,0,r.stderr)
  for c in self.call_list():
   self.assertFalse(set(c)&{'create','update','delete','apply','deploy','ssh','install','add'})
   if c[:2]!=['extension','show']:self.assertEqual(c[c.index('--subscription')+1],SUB)
  self.assertEqual(json.loads((self.out/'vendor-identity-comparison.json').read_text())['identity_comparison'],'MATCH')
  self.assertIn('NOT_PERFORMED',(self.out/'summary.txt').read_text());self.assertIn('completed_utc=',(self.out/'timing.txt').read_text())
  self.assertTrue((self.out/'vendor-runtime-evidence-REQUIRED.txt').exists())
  calls=self.call_list();self.assertTrue(any(c[:4]==['network','vnet','peering','list'] and c[c.index('--vnet-name')+1]=='management' for c in calls));self.assertTrue((self.out/'hub-connections.json').exists());self.assertTrue((self.out/'app-bastion-subnet.json').exists())
 def test_invalid_uuid_no_reads(self):
  self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='wrong').returncode,0);self.assertFalse(self.calls.exists())
 def test_wrong_subscription_no_reads(self):
  self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='22222222-2222-2222-2222-222222222222').returncode,0);self.assertFalse(self.calls.exists())
 def test_wrong_vm_targets_rejected_before_azure_reads(self):
  for role in ('app','origin'):
   key=role+'_vm_id';good=data()[key]['value']
   for bad in (None,123,good.replace(SUB,'22222222-2222-2222-2222-222222222222'),good.replace('inspection-partner','other-rg'),good.replace('Microsoft.Compute','Microsoft.Network'),good+'-other'):
    with self.subTest(role=role,target=bad):
     self.state.write_text(json.dumps(data()));self.modify(key,bad);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_missing_vm_targets_rejected_before_azure_reads(self):
  for role in ('app','origin'):
   values=data();del values[role+'_vm_id'];self.state.write_text(json.dumps(values));self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_wrong_nic_targets_rejected_before_azure_reads(self):
  good=data()['nic_ids']['value']
  bad_maps=[None,[],{},dict(good,extra=ARM+'networkInterfaces/extra'),{'app':good['app']}]
  for role in ('app','origin'):
   for bad in (None,123,good[role].replace(SUB,'22222222-2222-2222-2222-222222222222'),good[role].replace('inspection-partner','other-rg'),good[role].replace('networkInterfaces','publicIPAddresses'),good[role]+'-other'):
    bad_maps.append(dict(good,**{role:bad}))
  for bad in bad_maps:
   with self.subTest(targets=bad):
    self.modify('nic_ids',bad);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_missing_nic_targets_rejected_before_azure_reads(self):
  values=data();del values['nic_ids'];self.state.write_text(json.dumps(values));self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_private_handling_notice_and_unredacted_operator_text(self):
  p=dict(PROFILE);p['evidence_reference']='nonsecret-operator-text-retained-verbatim';self.modify('vendor_profile',p)
  result=self.run_collector();self.assertEqual(result.returncode,0,result.stderr)
  note=(self.out/'PRIVATE-HANDLING-REQUIRED.txt').read_text()
  for token in ('client-side','secret-bearing','without redaction','Enter no secrets','before sharing'):self.assertIn(token,note)
  saved=json.loads((self.out/'terraform-outputs.json').read_text());self.assertEqual(saved['vendor_profile']['value']['evidence_reference'],p['evidence_reference'])
  self.assertEqual(self.out.stat().st_mode&0o777,0o700);self.assertEqual((self.out/'terraform-outputs.json').stat().st_mode&0o777,0o600)
 def test_disabled_no_reads(self):
  self.modify('deployment_enabled',False);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_wrong_external_hub_no_reads(self):
  p=dict(PROFILE);p['hub_resource_id']=ARM+'virtualHubs/other';self.modify('vendor_profile',p);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_vm_substitute_no_reads(self):
  p=dict(PROFILE);p['nva_resource_id']=f'/subscriptions/{SUB}/resourceGroups/vendor-managed/providers/Microsoft.Compute/virtualMachines/fake';self.modify('vendor_profile',p);self.modify('nva_resource_id',p['nva_resource_id']);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_bootstrap_profile_absent_is_explicit_blocker(self):
  self.modify('vendor_profile',None);self.modify('nva_resource_id',None);self.modify('routing_intent_id',None)
  self.assertEqual(self.run_collector().returncode,0);self.assertTrue((self.out/'vendor-profile-BLOCKED.txt').exists());self.assertFalse((self.out/'nva-projected.json').exists())
 def test_omitted_optional_vendor_and_intent_outputs(self):
  values=json.loads(self.state.read_text())
  for k in ['vendor_profile','nva_resource_id','routing_intent_id']:del values[k]
  self.state.write_text(json.dumps(values));result=self.run_collector();self.assertEqual(result.returncode,0,result.stderr);self.assertNotIn('KeyError',result.stderr);self.assertTrue((self.out/'vendor-profile-BLOCKED.txt').exists());self.assertFalse((self.out/'nva-projected.json').exists());self.assertFalse((self.out/'intent.json').exists())
  for c in self.call_list():
   if '--ids' in c:self.assertTrue(c[c.index('--ids')+1])
 def test_omitted_required_owned_id_still_rejected(self):
  values=json.loads(self.state.read_text());del values['vwan_id'];self.state.write_text(json.dumps(values));self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_existing_output_refused(self):
  self.out.mkdir();(self.out/'keep').write_text('old');self.assertNotEqual(self.run_collector().returncode,0);self.assertEqual((self.out/'keep').read_text(),'old')
 def test_missing_extension_no_resource_reads(self):
  self.assertNotEqual(self.run_collector(MOCK_MISSING_EXT='1').returncode,0);self.assertFalse(self.out.exists());self.assertTrue(all(c[:2]==['extension','show'] for c in self.call_list()))
 def test_read_failures_preserved_and_collection_continues(self):
  self.assertEqual(self.run_collector(MOCK_FAIL='show-effective-route-table').returncode,3);self.assertEqual((self.out/'app-effective-routes.exit').read_text().strip(),'5');self.assertTrue((self.out/'nva-projected.json').exists())
 def test_actual_wrong_vendor_rejected(self):
  nva,app=projected();nva['vendor']='Other';(self.base/'nva').write_text(json.dumps(nva));self.assertEqual(self.run_collector().returncode,3);self.assertEqual((self.out/'vendor-identity-comparison.exit').read_text().strip(),'4')
 def test_empty_responses_not_identity_proof(self):
  self.assertEqual(self.run_collector(MOCK_EMPTY='1').returncode,3);self.assertEqual(json.loads((self.out/'vendor-identity-comparison.json').read_text())['identity_comparison'],'MISMATCH')
 def test_config_local_only_six_fields_nonclobber(self):
  r=self.run_config();self.assertEqual(r.returncode,0,r.stderr);v=json.loads(self.out.read_text());self.assertEqual(len(v),6);self.assertEqual(v['role'],'app');self.assertEqual(v['private_ip'],'10.10.1.10');self.assertFalse(self.calls.exists());self.assertEqual(self.out.stat().st_mode&0o777,0o600);self.assertNotEqual(self.run_config().returncode,0)
 def test_config_origin_role(self):
  self.assertEqual(self.run_config('origin').returncode,0);self.assertEqual(json.loads(self.out.read_text())['private_ip'],'10.30.1.20')
 def test_config_rejects_unsafe_pool(self):
  for value in [[],['198.51.100.80'],['224.0.0.1'],['100.64.0.1'],['20.40.1.10'],['20.40.2.10','20.40.2.10']]:
   with self.subTest(value=value):
    self.modify('egress_public_ips',value);self.assertNotEqual(self.run_config().returncode,0);self.assertFalse(self.out.exists())
 def test_config_rejects_documentation_origin(self):
  self.modify('origin_public_ip','203.0.113.10');self.assertNotEqual(self.run_config().returncode,0);self.assertFalse(self.out.exists())
if __name__=='__main__':unittest.main()
