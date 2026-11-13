"""Process-level collector mocks. No Azure or Terraform invocation."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
SUB='11111111-1111-1111-1111-111111111111'
class CollectorTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.t=Path(self.tmp.name);self.bin=self.t/'bin';self.bin.mkdir();self.calls=self.t/'calls'
  self.outputs={k:{'value':v} for k,v in {'deployment_enabled':True,'route_server_id':f'/subscriptions/{SUB}/resourceGroups/inspection-routeserver/providers/Microsoft.Network/virtualHubs/routeserver','resource_group_name':'inspection-routeserver'}.items()}
  self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'SUBSCRIPTION_ID':SUB,'MOCK_OUTPUTS':json.dumps(self.outputs),'MOCK_CALLS':str(self.calls)}
  self.executable('terraform','#!/usr/bin/env python3\nimport os\nprint(os.environ["MOCK_OUTPUTS"])\n')
  self.executable('az','#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["MOCK_CALLS"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nif os.environ.get("MOCK_FAIL") and "list-learned-routes" in " ".join(sys.argv):sys.exit(4)\nprint("[]")\n')
 def tearDown(self):self.tmp.cleanup()
 def executable(self,name,text):p=self.bin/name;p.write_text(text);p.chmod(0o755)
 def run_collector(self,out=None):return subprocess.run([str(R/'scripts/collect-control-plane.sh'),str(out or self.t/'out')],env=self.env,capture_output=True,text=True,timeout=15)
 def test_snapshot_scoped_and_nonempty(self):
  p=self.run_collector();self.assertEqual(p.returncode,0,p.stderr)
  calls=[json.loads(x) for x in self.calls.read_text().splitlines()];self.assertGreater(len(calls),25)
  self.assertTrue(all(x[-2:]==['--subscription',SUB] for x in calls));self.assertTrue(all('delete' not in x and 'create' not in x and 'update' not in x for x in calls))
  self.assertTrue((self.t/'out/app-effective-routes.json').exists());self.assertIn('completed_utc=',(self.t/'out/timing.txt').read_text());self.assertIn('shell_exit=0',(self.t/'out/timing.txt').read_text())
 def test_wrong_subscription_no_azure(self):
  self.env['SUBSCRIPTION_ID']='22222222-2222-2222-2222-222222222222';p=self.run_collector();self.assertNotEqual(p.returncode,0);self.assertFalse(self.calls.exists());self.assertFalse((self.t/'out').exists())
 def test_malformed_subscription_no_azure(self):
  self.env['SUBSCRIPTION_ID']='bad';self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_malformed_routeserver_id_no_azure(self):
  self.outputs['route_server_id']['value']='fake/'+SUB;self.env['MOCK_OUTPUTS']=json.dumps(self.outputs);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_disabled_state_no_azure(self):
  self.outputs['deployment_enabled']['value']=False;self.env['MOCK_OUTPUTS']=json.dumps(self.outputs);self.assertNotEqual(self.run_collector().returncode,0);self.assertFalse(self.calls.exists())
 def test_existing_empty_directory_refused(self):
  out=self.t/'out';out.mkdir();self.assertNotEqual(self.run_collector(out).returncode,0);self.assertFalse(self.calls.exists());self.assertEqual(list(out.iterdir()),[])
 def test_existing_evidence_unchanged(self):
  out=self.t/'out';out.mkdir();(out/'sentinel').write_text('preserve');self.assertNotEqual(self.run_collector(out).returncode,0);self.assertEqual((out/'sentinel').read_text(),'preserve');self.assertFalse(self.calls.exists())
 def test_symlink_refused(self):
  target=self.t/'target';target.mkdir();out=self.t/'out';out.symlink_to(target,target_is_directory=True);self.assertNotEqual(self.run_collector(out).returncode,0);self.assertEqual(list(target.iterdir()),[])
 def test_two_runs_keep_independent_snapshots(self):
  self.assertEqual(self.run_collector(self.t/'one').returncode,0);self.assertEqual(self.run_collector(self.t/'two').returncode,0);self.assertTrue((self.t/'one/timing.txt').exists());self.assertTrue((self.t/'two/timing.txt').exists())
 def test_api_failure_retains_completion_and_partial_files(self):
  self.env['MOCK_FAIL']='1';p=self.run_collector();self.assertNotEqual(p.returncode,0);self.assertTrue((self.t/'out/routeserver.json').exists());self.assertIn('completed_utc=',(self.t/'out/timing.txt').read_text());self.assertIn('shell_exit=4',(self.t/'out/timing.txt').read_text())
if __name__=='__main__':unittest.main()
