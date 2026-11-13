"""Only fake Terraform/Azure CLI plus local JSON writes, no cloud requests."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
SUB='11111111-1111-1111-1111-111111111111';BASE=f'/subscriptions/{SUB}/resourceGroups/inspection-gwlb/providers/';NET=BASE+'Microsoft.Network/'
def data():
 v={'deployment_enabled':True,'resource_group_name':'inspection-gwlb','location':'westeurope','gwlb_id':NET+'loadBalancers/inspection-gwlb','consumer_lb_id':NET+'loadBalancers/public-lb','gwlb_frontend_id':NET+'loadBalancers/inspection-gwlb/frontendIPConfigurations/inspection-frontend','consumer_frontend_id':NET+'loadBalancers/public-lb/frontendIPConfigurations/public-frontend','consumer_public_ip_id':NET+'publicIPAddresses/consumer-public-ip','nva_pool_id':NET+'loadBalancers/inspection-gwlb/backendAddressPools/nva-pool','app_pool_id':NET+'loadBalancers/public-lb/backendAddressPools/app-pool','bastion_id':NET+'bastionHosts/management-bastion','bastion_name':'management-bastion','gwlb_frontend_private_ip':'10.0.2.10','backend_private_ip':'10.20.1.20','client_public_ip':'20.40.2.10','consumer_public_ip':'20.40.1.10'}
 for key,roles,prefix,suffix in [('vm_ids',['app','nva1','nva2'],BASE+'Microsoft.Compute/virtualMachines/',''),('nic_ids',['app','nva1','nva2'],NET+'networkInterfaces/','-nic'),('vnet_ids',['provider','consumer','management'],NET+'virtualNetworks/','')]:v[key]={role:prefix+role+suffix for role in roles}
 v['probe_ids']={'nva':NET+'loadBalancers/inspection-gwlb/probes/nva-readiness','app':NET+'loadBalancers/public-lb/probes/app-readiness'}
 return {k:{'value':x} for k,x in v.items()}
class OperatorTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name);self.bin=self.base/'bin';self.bin.mkdir();self.out=self.base/'out';self.state=self.base/'state';self.state.write_text(json.dumps(data()));self.calls=self.base/'calls'
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'SUBSCRIPTION_ID':SUB,'MOCK_STATE':str(self.state),'MOCK_CALLS':str(self.calls)}
  self.tool('terraform',"import os;print(open(os.environ['MOCK_STATE']).read())")
  self.tool('az',r'''
import json,os,sys
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\n')
if os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')!='no':raise SystemExit(9)
if '--subscription' not in args:raise SystemExit(8)
if os.environ.get('MOCK_FAIL') and os.environ['MOCK_FAIL'] in ' '.join(args):print('synthetic read error',file=sys.stderr);raise SystemExit(5)
print(json.dumps({'mock_only':True,'args':args}))
''')
 def tool(self,name,body):
  p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+body+'\n');p.chmod(0o755)
 def modify(self,key,value):
  d=json.loads(self.state.read_text());d[key]['value']=value;self.state.write_text(json.dumps(d))
 def runscript(self,name,**env):return subprocess.run(['bash',str(R/'scripts'/name),str(self.out)],capture_output=True,text=True,env={**self.env,**env})
 def collect(self,**env):return self.runscript('collect-control-plane.sh',**env)
 def config(self,**env):return self.runscript('make-client-config.sh',**env)
 def callslist(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
 def test_scoped_read_only_collection(self):
  r=self.collect();self.assertEqual(r.returncode,0,r.stderr)
  for args in self.callslist():
   self.assertEqual(args[args.index('--subscription')+1],SUB);self.assertFalse(set(args)&{'create','update','delete','apply','deploy','ssh','install','add','--debug','--verbose'})
   self.assertNotEqual(args[:2],['vm','show'])
  self.assertTrue((self.out/'inspection-lb.json').exists());self.assertTrue((self.out/'consumer-lb.json').exists());self.assertTrue((self.out/'nva2-effective-routes.json').exists());self.assertTrue((self.out/'app-effective-nsg.json').exists());self.assertTrue((self.out/'gwlb_id-metric-definitions.json').exists());self.assertIn('NOT_PERFORMED',(self.out/'summary.txt').read_text());self.assertIn('completed_utc=',(self.out/'timing.txt').read_text())
 def test_invalid_uuid_rejected(self):self.assertNotEqual(self.collect(SUBSCRIPTION_ID='bad').returncode,0);self.assertFalse(self.calls.exists())
 def test_wrong_subscription_rejected(self):self.assertNotEqual(self.collect(SUBSCRIPTION_ID='22222222-2222-2222-2222-222222222222').returncode,0);self.assertFalse(self.calls.exists())
 def test_disabled_rejected(self):self.modify('deployment_enabled',False);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_every_core_target_checked(self):
  for key in ['gwlb_id','consumer_lb_id','gwlb_frontend_id','consumer_frontend_id','consumer_public_ip_id','nva_pool_id','app_pool_id','bastion_id']:
   with self.subTest(key=key):
    self.state.write_text(json.dumps(data()));self.modify(key,data()[key]['value']+'-other');self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_missing_core_id_checked(self):
  d=data();del d['gwlb_frontend_id'];self.state.write_text(json.dumps(d));self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_missing_id_maps_checked(self):
  for key in ['vm_ids','nic_ids','vnet_ids','probe_ids']:
   with self.subTest(key=key):
    d=data();del d[key];self.state.write_text(json.dumps(d));self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_malformed_and_foreign_maps_checked(self):
  for key in ['vm_ids','nic_ids','vnet_ids','probe_ids']:
   good=data()[key]['value'];role=next(iter(good));bad=[None,[],{},dict(good,extra='wrong'),dict(good,**{role:None}),dict(good,**{role:good[role].replace('inspection-gwlb','foreign')})]
   for value in bad:
    with self.subTest(key=key,value=value):
     self.state.write_text(json.dumps(data()));self.modify(key,value);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_existing_directory_refused(self):self.out.mkdir();(self.out/'keep').write_text('old');self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists());self.assertEqual((self.out/'keep').read_text(),'old')
 def test_symlink_refused(self):
  target=self.base/'existing';target.mkdir();self.out.symlink_to(target,target_is_directory=True);self.assertNotEqual(self.collect().returncode,0);self.assertFalse(self.calls.exists())
 def test_failed_reads_retained_and_continued(self):self.assertEqual(self.collect(MOCK_FAIL='show-effective-route-table').returncode,3);self.assertEqual((self.out/'nva1-effective-routes.exit').read_text().strip(),'5');self.assertTrue((self.out/'bastion.json').exists())
 def test_private_unredacted_declared_outputs(self):
  d=data();d['operator_note']={'value':'nonsecret-mock-text-retained'};self.state.write_text(json.dumps(d));self.assertEqual(self.collect().returncode,0);self.assertIn('client-side',(self.out/'PRIVATE-HANDLING-REQUIRED.txt').read_text());self.assertIn('not automatically redacted',(self.out/'PRIVATE-HANDLING-REQUIRED.txt').read_text());self.assertEqual(json.loads((self.out/'terraform-outputs.json').read_text())['operator_note']['value'],'nonsecret-mock-text-retained');self.assertEqual(self.out.stat().st_mode&0o777,0o700)
 def test_config_is_local_exact_and_private(self):
  r=self.config();self.assertEqual(r.returncode,0,r.stderr);v=json.loads(self.out.read_text());self.assertEqual(v,{'client_public_ip':'20.40.2.10','consumer_public_ip':'20.40.1.10','backend_ip':'10.20.1.20'});self.assertEqual(self.out.stat().st_mode&0o777,0o600);self.assertFalse(self.calls.exists());self.assertNotEqual(self.config().returncode,0)
 def test_config_bad_public_values_rejected(self):
  for key in ['client_public_ip','consumer_public_ip']:
   for value in ['10.1.2.3','100.64.1.1','203.0.113.10','224.0.0.1','20.40.1.10' if key=='client_public_ip' else '20.40.2.10']:
    with self.subTest(key=key,value=value):
     self.state.write_text(json.dumps(data()));self.modify(key,value);self.assertNotEqual(self.config().returncode,0);self.assertFalse(self.out.exists());self.assertFalse(self.calls.exists())
if __name__=='__main__':unittest.main()
