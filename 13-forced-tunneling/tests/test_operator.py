"""Fake Terraform/Azure CLI only. No cloud identity, APIs, secret or resource changes."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SUB='11111111-1111-1111-1111-111111111111'
BASE=f'/subscriptions/{SUB}/resourceGroups/inspection-forced/providers/'
NET=BASE+'Microsoft.Network/'
class OperatorTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name);self.bin=self.base/'bin';self.bin.mkdir();self.out=self.base/'evidence';self.calls=self.base/'calls'
  values={'deployment_enabled':True,'resource_group_name':'inspection-forced','firewall_name':'hub-firewall','firewall_private_ip':'10.0.1.4','firewall_id':NET+'azureFirewalls/hub-firewall','firewall_policy_id':NET+'firewallPolicies/forced-policy','workspace_id':BASE+'Microsoft.OperationalInsights/workspaces/forced-logs','bastion_id':NET+'bastionHosts/management-bastion','bastion_name':'management-bastion','source_mode':'preserve','perimeter_source_prefix':'10.20.1.10/32','private_ips':{'app':'10.20.1.10','perimeter':'10.30.1.4','origin':'10.50.1.20'},'public_ips':{'perimeter':'20.50.0.20','origin':'20.42.0.10'},'vm_ids':{k:BASE+'Microsoft.Compute/virtualMachines/'+k for k in ['app','perimeter','origin']},'nic_ids':{k:NET+'networkInterfaces/'+k+'-nic' for k in ['app','perimeter','origin']},'vnet_ids':{k:NET+'virtualNetworks/'+k for k in ['hub','app','perimeter','origin','management']},'route_table_ids':{k:NET+'routeTables/'+n for k,n in {'app':'app-forced-default','firewall':'firewall-to-perimeter','perimeter':'perimeter-return'}.items()},'public_ip_ids':{k:NET+'publicIPAddresses/'+n for k,n in {'perimeter':'perimeter-public-ip','origin':'origin-public-ip','firewall_management':'firewall-management-public-ip','bastion':'management-bastion-public-ip'}.items()}}
  self.state=self.base/'outputs.json';self.state.write_text(json.dumps({k:{'value':v} for k,v in values.items()}))
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'SUBSCRIPTION_ID':SUB,'MOCK_STATE':str(self.state),'MOCK_CALLS':str(self.calls)}
  self.tool('terraform',"import os;print(open(os.environ['MOCK_STATE']).read())")
  self.tool('az',r'''
import os,sys,json
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\n')
if os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')!='no':raise SystemExit(9)
if '--subscription' not in args:raise SystemExit(8)
if os.environ.get('MOCK_FAIL') and os.environ['MOCK_FAIL'] in ' '.join(args):
 print('synthetic private read error',file=sys.stderr);raise SystemExit(5)
print('[]' if os.environ.get('MOCK_EMPTY') else json.dumps({'mock_only':True,'args':args}))
''')
 def tool(self,name,body):
  p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+body+'\n');p.chmod(0o755)
 def change(self,key,value):
  v=json.loads(self.state.read_text());v[key]={'value':value};self.state.write_text(json.dumps(v))
 def omit(self,key):
  v=json.loads(self.state.read_text());del v[key];self.state.write_text(json.dumps(v))
 def run_collector(self,*args,**env):
  return subprocess.run(['bash',str(ROOT/'scripts/collect-control-plane.sh'),*args,str(self.out)],env={**self.env,**env},capture_output=True,text=True)
 def reads(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
 def blocked(self):
  p=self.run_collector();self.assertNotEqual(p.returncode,0,p.stdout);self.assertFalse(self.calls.exists())
 def test_all_reads_subscription_scoped_and_no_changes(self):
  self.assertEqual(self.run_collector().returncode,0)
  for c in self.reads():
   self.assertEqual(c[c.index('--subscription')+1],SUB)
   self.assertFalse(set(c)&{'create','update','delete','apply','destroy','install','reset','show-shared-key','shared-key','get-shared-key','ssh'})
  self.assertGreater(len(self.reads()),25)

 def test_invalid_uuid(self):
  self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='bad').returncode,0);self.assertFalse(self.calls.exists())

 def test_wrong_subscription(self):
  self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='22222222-2222-2222-2222-222222222222').returncode,0);self.assertFalse(self.calls.exists())

 def test_disabled_root(self):self.change('deployment_enabled',False);self.blocked()

 def test_foreign_firewall(self):self.change('firewall_id',NET+'azureFirewalls/production');self.blocked()

 def test_foreign_policy(self):self.change('firewall_policy_id',NET+'firewallPolicies/production');self.blocked()

 def test_foreign_workspace(self):self.change('workspace_id',BASE+'Microsoft.OperationalInsights/workspaces/production');self.blocked()

 def test_allocated_firewall_not_assumed_dot4(self):self.change('firewall_private_ip','10.0.1.5');self.assertEqual(self.run_collector().returncode,0)

 def test_firewall_wrong_subnet(self):self.change('firewall_private_ip','10.1.1.4');self.blocked()

 def test_reserved_firewall_address(self):self.change('firewall_private_ip','10.0.1.2');self.blocked()

 def test_omitted_nic_map(self):self.omit('nic_ids');self.blocked()

 def test_extra_vnet(self):self.change('vnet_ids',{});self.blocked()

 def test_wrong_route_map(self):self.change('route_table_ids',{});self.blocked()

 def test_existing_output_refused(self):
  self.out.mkdir();(self.out/'sentinel').write_text('keep');self.assertNotEqual(self.run_collector().returncode,0);self.assertEqual((self.out/'sentinel').read_text(),'keep');self.assertFalse(self.calls.exists())

 def test_symlink_output_refused(self):
  target=self.base/'other';target.mkdir();self.out.symlink_to(target,target_is_directory=True);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())

 def test_read_failure_retained(self):
  p=self.run_collector(MOCK_FAIL='show-effective-route-table');self.assertEqual(p.returncode,3)
  self.assertEqual((self.out/'app-effective-routes.exit').read_text().strip(),'5');self.assertIn('synthetic private',(self.out/'app-effective-routes.stderr').read_text())

 def test_empty_read_is_not_verification(self):
  p=self.run_collector(MOCK_EMPTY='1');self.assertEqual(p.returncode,0,p.stderr);self.assertIn('route_verification=NOT_PERFORMED',(self.out/'summary.txt').read_text())

 def test_completion_and_private_receipt(self):
  self.assertEqual(self.run_collector().returncode,0)
  self.assertIn('completed_utc=',(self.out/'timing.txt').read_text());self.assertIn('client',(self.out/'PRIVATE-HANDLING-REQUIRED.txt').read_text());self.assertEqual(self.out.stat().st_mode&0o777,0o700)

 def test_unknown_optin_flag(self):self.assertNotEqual(self.run_collector('--ack').returncode,0);self.assertFalse(self.calls.exists())

 def test_mode_scope_mismatch(self):self.change('source_mode','firewall_private');self.blocked()
 def test_private_mode_exact_scope(self):self.change('source_mode','firewall_private');self.change('perimeter_source_prefix','10.0.1.0/26');self.assertEqual(self.run_collector().returncode,0)
 def test_missing_null_or_foreign_all_id_maps(self):
  initial=self.state.read_text()
  for key in ['vm_ids','nic_ids','vnet_ids','route_table_ids','public_ip_ids']:
   for value in [None,{}, {'prod':'bad'}]:
    self.state.write_text(initial);self.change(key,value);self.blocked()
   self.state.write_text(initial);self.omit(key);self.blocked()
 def test_public_destination_not_documentation_or_private(self):
  for ip in ['203.0.113.1','10.0.0.1','224.0.0.1','192.88.99.1','20.50.0.20']:
   self.change('public_ips',{'origin':ip,'perimeter':'20.50.0.20'});self.blocked()
 def test_nonstring_public_and_firewall_rejected(self):
  self.change('firewall_private_ip',167772420);self.blocked()
  self.change('firewall_private_ip','10.0.1.4');self.change('public_ips',{'origin':134744072,'perimeter':'20.50.0.20'});self.blocked()
 def test_no_gateway_or_secret_reads(self):
  self.assertEqual(self.run_collector().returncode,0)
  for c in self.reads():self.assertFalse(set(c)&{'vpn-connection','vnet-gateway','get-shared-key','shared-key','vm'})
if __name__=='__main__':unittest.main()
