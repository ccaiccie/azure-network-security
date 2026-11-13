"""Fake az/Terraform only. No cloud APIs, deployment or real environment identity."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
SUB = '11111111-1111-1111-1111-111111111111'
ARM = f'/subscriptions/{SUB}/resourceGroups/inspection-vwan/providers/Microsoft.Network/'

class OperatorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name); self.bin = self.base/'bin'; self.bin.mkdir()
        values = dict(deployment_enabled=True, resource_group_name='inspection-vwan', hub_name='secured-hub',
                      firewall_id=ARM+'azureFirewalls/hub-firewall', hub_id=ARM+'virtualHubs/secured-hub',
                      vwan_id=ARM+'virtualWans/lab-wan', firewall_policy_id=ARM+'firewallPolicies/private-policy',
                      routing_intent_id=ARM+'virtualHubs/secured-hub/routingIntent/private-inspection',
                      hub_default_route_table_id=ARM+'virtualHubs/secured-hub/hubRouteTables/defaultRouteTable')
        self.state = self.base/'state.json'; self.state.write_text(json.dumps({k:{'value':v} for k,v in values.items()}))
        self.calls=self.base/'calls'; self.out=self.base/'evidence'
        self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'], 'SUBSCRIPTION_ID':SUB,
                  'MOCK_STATE':str(self.state),'MOCK_CALLS':str(self.calls)}
        self.tool('terraform',"import os;print(open(os.environ['MOCK_STATE']).read())")
        self.tool('az',r'''
import json,os,sys
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\n')
if os.environ.get('AZURE_EXTENSION_USE_DYNAMIC_INSTALL')!='no':raise SystemExit(9)
if args[:2]==['extension','show']:
 if os.environ.get('MOCK_MISSING_EXT')==args[args.index('--name')+1]:raise SystemExit(4)
 print(args[args.index('--name')+1]);raise SystemExit(0)
if '--subscription' not in args:raise SystemExit(8)
if os.environ.get('MOCK_FAIL') and os.environ['MOCK_FAIL'] in ' '.join(args):
 print('synthetic read failure',file=sys.stderr);raise SystemExit(5)
print('[]' if os.environ.get('MOCK_EMPTY') else json.dumps({'mock_only':True,'args':args}))
''')
    def tool(self,name,body):
        p=self.bin/name;p.write_text('#!/usr/bin/env python3\n'+body+'\n');p.chmod(0o755)
    def run_collector(self,**env):
        return subprocess.run(['bash',str(ROOT/'scripts/collect-control-plane.sh'),str(self.out)],env={**self.env,**env},text=True,capture_output=True)
    def calls_read(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
    def test_scoped_readonly(self):
        r=self.run_collector();self.assertEqual(r.returncode,0,r.stderr)
        calls=self.calls_read();self.assertGreater(len(calls),20)
        for c in calls:
            self.assertFalse(set(c)&{'create','update','delete','apply','deploy','ssh','install','add'})
            if c[:2]!=['extension','show']:self.assertEqual(c[c.index('--subscription')+1],SUB)
        self.assertIn('route_verification=NOT_PERFORMED',(self.out/'summary.txt').read_text())
        self.assertIn('completed_utc=',(self.out/'timing.txt').read_text())
        self.assertTrue((self.out/'firewall-onward-routes-REQUIRED.txt').exists())
        self.assertFalse((self.out/'firewall-effective-routes-candidate.json').exists())
    def test_invalid_uuid_prevents_calls(self):
        self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='wrong').returncode,0);self.assertFalse(self.calls.exists())
    def test_wrong_subscription_prevents_calls(self):
        self.assertNotEqual(self.run_collector(SUBSCRIPTION_ID='22222222-2222-2222-2222-222222222222').returncode,0);self.assertFalse(self.calls.exists())
    def test_disabled_prevents_calls(self):
        data=json.loads(self.state.read_text());data['deployment_enabled']['value']=False;self.state.write_text(json.dumps(data))
        self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
    def test_bad_hub_id_prevents_calls(self):
        data=json.loads(self.state.read_text());data['hub_id']['value']=ARM+'virtualNetworks/hub';self.state.write_text(json.dumps(data))
        self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
    def test_foreign_secondary_id_prevents_reads(self):
        data=json.loads(self.state.read_text());data['vwan_id']['value']=data['vwan_id']['value'].replace(SUB,'22222222-2222-2222-2222-222222222222');self.state.write_text(json.dumps(data))
        self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
    def test_foreign_policy_name_prevents_reads(self):
        data=json.loads(self.state.read_text());data['firewall_policy_id']['value']=ARM+'firewallPolicies/shared-policy';self.state.write_text(json.dumps(data))
        self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
    def test_existing_output_refused(self):
        self.out.mkdir();(self.out/'keep').write_text('old')
        self.assertNotEqual(self.run_collector().returncode,0);self.assertEqual((self.out/'keep').read_text(),'old')
        self.assertTrue(all(c[:2]==['extension','show'] for c in self.calls_read()))
    def test_missing_extension_no_resource_reads(self):
        self.assertNotEqual(self.run_collector(MOCK_MISSING_EXT='virtual-wan').returncode,0)
        self.assertFalse(self.out.exists());self.assertTrue(all(c[:2]==['extension','show'] for c in self.calls_read()))
    def test_partial_read_failure_preserved_and_continues(self):
        self.assertEqual(self.run_collector(MOCK_FAIL='show-effective-route-table').returncode,3)
        self.assertEqual((self.out/'app-effective-routes.exit').read_text().strip(),'5')
        self.assertIn('synthetic',(self.out/'app-effective-routes.stderr').read_text())
        self.assertTrue((self.out/'firewall-metric-definitions.json').exists())
        self.assertIn('collection_failures=2',(self.out/'summary.txt').read_text())
    def test_candidate_is_unverified_and_failure_retained(self):
        self.assertEqual(self.run_collector(FIREWALL_ROUTE_RESOURCE_TYPE='AzureFirewalls',MOCK_FAIL='AzureFirewalls').returncode,3)
        self.assertIn('UNVERIFIED',(self.out/'firewall-candidate-NOT-VERIFIED.txt').read_text())
        self.assertEqual((self.out/'firewall-effective-routes-candidate.exit').read_text().strip(),'5')
    def test_empty_success_never_verifies_routes(self):
        self.assertEqual(self.run_collector(MOCK_EMPTY='1',FIREWALL_ROUTE_RESOURCE_TYPE='AzureFirewalls').returncode,0)
        self.assertIn('NOT_PERFORMED',(self.out/'summary.txt').read_text())
        self.assertIn('NOT verification',(self.out/'firewall-onward-routes-REQUIRED.txt').read_text())
    def test_invalid_candidate_rejected_before_resource_calls(self):
        self.assertNotEqual(self.run_collector(FIREWALL_ROUTE_RESOURCE_TYPE='--bad type').returncode,0)
        self.assertFalse(self.out.exists());self.assertTrue(all(c[:2]==['extension','show'] for c in self.calls_read()))

if __name__=='__main__':unittest.main()
