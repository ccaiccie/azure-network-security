#!/usr/bin/env python3
"""Actual loopback HTTP fixture + fake-tool probes, never Azure or private DNS."""
import contextlib,http.client,importlib.util,io,json,os,subprocess,sys,tempfile,threading,unittest
sys.dont_write_bytecode=True
from pathlib import Path
R=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('fixture',R/'fixtures/server.py');fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
class FixtureTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.server=fixture.make_server('127.0.0.1',0);cls.port=cls.server.server_address[1];cls.server.expected_host_port=8080
  cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.thread.join()
 def request(self,path='/probe',host='allowed.policy.test:8080',method='GET',extra=None):
  c=http.client.HTTPConnection('127.0.0.1',self.port,timeout=3)
  c.request(method,path,headers={'Host':host,'X-Lab-Case-ID':'local-case','User-Agent':'azure-policy-lab/local-case',**(extra or {})});r=c.getresponse();status=r.status;headers=dict(r.getheaders());body=r.read();c.close();return status,headers,body
 def test_both_names_healthy(self):
  for host in ['allowed.policy.test:8080','denied.policy.test:8080']:
   status,h,b=self.request(host=host);v=json.loads(b);self.assertEqual(status,200);self.assertEqual(v['fixture'],'azure-policy-origin-v1');self.assertEqual(v['host'],host);self.assertEqual(v['case_id'],'local-case');self.assertEqual(v['peer_ip'],'127.0.0.1');self.assertEqual(v['server_port'],self.port);self.assertEqual(h['Cache-Control'],'no-store')
 def test_health(self):self.assertEqual(self.request('/health')[0],200)
 def test_paths_exact(self):
  for p in ['/','/probe/','/probe?q=1','/../../etc/passwd']:self.assertEqual(self.request(p)[0],404)
 def test_nonget(self):self.assertEqual(self.request(method='POST')[0],405)
 def test_wrong_host_or_port(self):
  for host in ['allowed.policy.test','allowed.policy.test:80','other.policy.test:8080']:self.assertEqual(self.request(host=host)[0],400)
 def test_bad_case(self):self.assertEqual(self.request(extra={'X-Lab-Case-ID':'bad value'})[0],400)
 def test_bounded_path(self):self.assertEqual(self.request('/'+'a'*300)[0],414)
 def test_bounded_headers(self):self.assertEqual(self.request(extra={'X-Extra':'a'*9000})[0],431)
 def test_xff_explicit_untrusted(self):
  row=json.loads(self.request(extra={'X-Forwarded-For':'arbitrary'})[2]);self.assertEqual(row['xff_untrusted'],'arbitrary');self.assertEqual(row['peer_ip'],'127.0.0.1')
 def test_bounded_server_configuration(self):
  self.assertEqual(self.server.request_queue_size,16);self.assertTrue(self.server.daemon_threads)
 def test_cli_rejects_public_bind(self):
  r=subprocess.run(['python3',str(R/'fixtures/server.py'),'--bind','0.0.0.0','--port','8080'],capture_output=True);self.assertNotEqual(r.returncode,0)
 def test_cli_rejects_other_port(self):
  r=subprocess.run(['python3',str(R/'fixtures/server.py'),'--bind','10.20.1.10','--port','80'],capture_output=True);self.assertNotEqual(r.returncode,0)
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name;a=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps({'cmd':name,'args':a})+'\n')
if name=='ip':print('2: eth0 inet '+os.environ.get('MOCK_IP','10.10.1.10')+'/24 scope global');sys.exit()
if name=='getent':print(os.environ.get('MOCK_DNS','10.20.1.10')+' STREAM '+a[-1]);sys.exit()
if name=='resolvectl':print('MOCK DNS F=10.0.1.4');sys.exit()
if name=='terraform':print(Path(os.environ['MOCK_TF']).read_text());sys.exit()
if name=='az':print('{}');sys.exit()
if name=='curl':
 if a==['-V']:print('curl MOCK');sys.exit()
 assert a[0]=='-q'
 from urllib.parse import urlparse
 u=urlparse(a[-1]);case=a[a.index('--header')+1].split(': ',1)[1]
 out=Path(a[a.index('--output')+1]);headers=Path(a[a.index('--dump-header')+1]);headers.write_text('MOCK response')
 out.write_text(json.dumps({'fixture':os.environ.get('MOCK_FIXTURE','azure-policy-origin-v1'),'case_id':case,'host':u.netloc,'path':u.path,'server_ip':'10.20.1.10','server_port':u.port,'peer_ip':os.environ.get('MOCK_PEER','10.0.1.5'),'peer_port':54321,'xff_untrusted':'10.10.1.10'}))
 print('http='+os.environ.get('MOCK_HTTP','200')+' local=10.10.1.10:43210 remote=10.20.1.10:'+str(u.port)+' seconds=0.001');sys.exit(int(os.environ.get('MOCK_RC','0')))
raise SystemExit('Unexpected fake command')
'''
class HelperTests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.p=Path(self.t.name);self.bin=self.p/'bin';self.bin.mkdir()
  for n in ['ip','getent','resolvectl','terraform','az','curl']:
   p=self.bin/n;p.write_text(FAKE);p.chmod(0o755)
  self.log=self.p/'calls.jsonl';self.config=self.p/'config.json';self.config.write_text(json.dumps({'role':'app','private_ip':'10.10.1.10','backend_ip':'10.20.1.10','firewall_ip':'10.0.1.4','allowed_host':'allowed.policy.test','denied_host':'denied.policy.test'}))
  sub='11111111-1111-1111-1111-111111111111';self.tf=self.p/'outputs.json';self.tf.write_text(json.dumps({k:{'value':v} for k,v in {'deployment_enabled':True,'resource_group_name':'mock','firewall_id':f'/subscriptions/{sub}/resourceGroups/mock/providers/Microsoft.Network/azureFirewalls/lab-firewall'}.items()}))
  self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'POLICY_LAB_CONFIG':str(self.config),'MOCK_LOG':str(self.log),'MOCK_TF':str(self.tf),'SUBSCRIPTION_ID':sub,'HOME':str(self.p)}
 def tearDown(self):self.t.cleanup()
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
 def run_script(self,script,*args,extra=None):return subprocess.run(['bash',str(R/'scripts'/script),*map(str,args)],env={**self.env,**(extra or {})},capture_output=True,text=True,cwd=R)
 def probe(self,kind='allowed',extra=None):return self.run_script('guest-probe.sh',kind,self.p/'result',extra=extra)
 def curl_request(self):return next(c['args'] for c in self.calls() if c['cmd']=='curl' and c['args']!=['-V'])
 def test_application_source_class(self):
  r=self.probe();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('FIXTURE_IDENTITY=MATCH',r.stdout);self.assertIn('FIREWALL_SUBNET_PROXY_SOURCE actual=10.0.1.5',r.stdout);self.assertIn('NEEDS_REVIEW',r.stdout)
 def test_network_source_class(self):self.assertIn('DIRECT_APP_SOURCE',self.probe(extra={'MOCK_PEER':'10.10.1.10'}).stdout)
 def test_unexpected_peer_flagged(self):self.assertIn('UNEXPECTED_SOURCE',self.probe(extra={'MOCK_PEER':'10.20.1.20'}).stdout)
 def test_denied_host_can_succeed_under_network_mode(self):
  r=self.probe('denied',{'MOCK_PEER':'10.10.1.10'});self.assertIn('FIXTURE_IDENTITY=MATCH',r.stdout);self.assertEqual(self.curl_request()[-1],'http://denied.policy.test:8080/probe')
 def test_alternate_port(self):
  self.probe('alternate-port');self.assertEqual(self.curl_request()[-1],'http://allowed.policy.test:8081/probe')
 def test_proxy_and_config_disabled(self):
  self.probe();a=self.curl_request();self.assertEqual(a[0],'-q');self.assertIn('--proxy',a);self.assertIn('--noproxy',a);self.assertNotIn('--resolve',a);self.assertNotIn('--location',a);self.assertIn('--connect-timeout',a);self.assertIn('--max-time',a)
 def test_user_agent_matches_case(self):
  self.probe();a=self.curl_request();case=a[a.index('--header')+1].split(': ',1)[1];self.assertEqual(a[a.index('--user-agent')+1],'azure-policy-lab/'+case)
 def test_bad_dns_stops_before_request(self):
  r=self.probe(extra={'MOCK_DNS':'10.20.1.99'});self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd']=='curl' and c['args']!=['-V'] for c in self.calls()))
 def test_wrong_vm(self):self.assertNotEqual(self.probe(extra={'MOCK_IP':'10.10.1.11'}).returncode,0)
 def test_wrong_role(self):
  c=json.loads(self.config.read_text());c['role']='backend';self.config.write_text(json.dumps(c));self.assertNotEqual(self.probe().returncode,0)
 def test_proxy_error_not_fixture(self):
  r=self.probe(extra={'MOCK_FIXTURE':'firewall-error-page','MOCK_HTTP':'403'});self.assertIn('MISMATCH',r.stdout);self.assertNotIn('FIXTURE_IDENTITY=MATCH',r.stdout)
 def test_transport_failure_recorded(self):
  r=self.probe(extra={'MOCK_RC':'28','MOCK_HTTP':'000'});self.assertEqual(r.returncode,0);self.assertIn('curl_exit=28',r.stdout);self.assertIn('NEEDS_REVIEW',r.stdout)
 def test_unknown_case_rejected(self):self.assertNotEqual(self.probe('invalid').returncode,0)
 def test_collector_resource_calls_scoped_and_readonly(self):
  r=self.run_script('collect-control-plane.sh',self.p/'evidence');self.assertEqual(r.returncode,0,r.stderr)
  calls=[c['args'] for c in self.calls() if c['cmd']=='az'];self.assertGreater(len(calls),20)
  self.assertIn('completed_utc=',(self.p/'evidence/timing.txt').read_text())
  for a in calls:
   if a[:2]==['extension','show']:continue
   self.assertIn('--subscription',a);self.assertEqual(a[a.index('--subscription')+1],self.env['SUBSCRIPTION_ID']);self.assertFalse(any(x in a for x in ['create','update','delete','apply','set','deploy']))
 def test_collector_wrong_subscription_stops(self):
  r=self.run_script('collect-control-plane.sh',self.p/'evidence',extra={'SUBSCRIPTION_ID':'22222222-2222-2222-2222-222222222222'});self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_existing_nonempty_evidence_refused_untouched(self):
  out=self.p/'result';out.mkdir();(out/'response.body').write_text('prior successful case');(out/'case.txt').write_text('prior case')
  before={p.name:p.read_bytes() for p in out.iterdir()}
  r=self.probe();self.assertNotEqual(r.returncode,0);self.assertIn('already exists or cannot be created',r.stderr)
  self.assertEqual(before,{p.name:p.read_bytes() for p in out.iterdir()});self.assertFalse(any(c['cmd']=='curl' for c in self.calls()))
 def test_existing_empty_evidence_refused(self):
  (self.p/'result').mkdir();r=self.probe();self.assertNotEqual(r.returncode,0);self.assertEqual(list((self.p/'result').iterdir()),[])
 def test_existing_symlink_evidence_refused(self):
  target=self.p/'prior';target.mkdir();(target/'response.body').write_text('keep');(self.p/'result').symlink_to(target,target_is_directory=True)
  r=self.probe();self.assertNotEqual(r.returncode,0);self.assertEqual((target/'response.body').read_text(),'keep')
 def test_rerun_fixed_out_cannot_overwrite(self):
  first=self.probe();self.assertEqual(first.returncode,0);before={p.name:p.read_bytes() for p in (self.p/'result').iterdir()}
  second=self.probe('denied');self.assertNotEqual(second.returncode,0);self.assertEqual(before,{p.name:p.read_bytes() for p in (self.p/'result').iterdir()})
 def test_default_case_dirs_distinct(self):
  first=self.run_script('guest-probe.sh','allowed');second=self.run_script('guest-probe.sh','allowed')
  self.assertEqual(first.returncode,0,first.stderr);self.assertEqual(second.returncode,0,second.stderr);self.assertEqual(len(list((self.p/'policy-evidence').iterdir())),2)
 def test_probe_completion_timestamps(self):
  from datetime import datetime
  r=self.probe();self.assertEqual(r.returncode,0)
  rows=dict(line.split('=',1) for line in (self.p/'result/timing.txt').read_text().splitlines())
  self.assertLessEqual(datetime.fromisoformat(rows['started_utc']),datetime.fromisoformat(rows['completed_utc']));self.assertEqual(rows['shell_exit'],'0')
 def test_probe_completion_on_dns_failure(self):
  r=self.probe(extra={'MOCK_DNS':'10.20.1.99'});self.assertNotEqual(r.returncode,0)
  rows=dict(line.split('=',1) for line in (self.p/'result/timing.txt').read_text().splitlines());self.assertIn('completed_utc',rows);self.assertNotEqual(rows['shell_exit'],'0')
 def test_collector_existing_out_refused_untouched(self):
  out=self.p/'evidence';out.mkdir();(out/'policy.json').write_text('prior config')
  r=self.run_script('collect-control-plane.sh',out);self.assertNotEqual(r.returncode,0);self.assertEqual((out/'policy.json').read_text(),'prior config');self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_ready_wrong_role_stops_without_network(self):
  r=self.run_script('guest-ready.sh');self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd'] in ['az','curl','getent'] for c in self.calls()))
class ReadinessTests(unittest.TestCase):
 def run_ready(self,role='backend',inactive=False,changes=None):
  from unittest.mock import patch
  from urllib.parse import urlparse
  from types import SimpleNamespace
  source=(R/'scripts/guest-ready.sh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
  calls=[]
  def process(args,**kwargs):
   if args[0]=='ip':return SimpleNamespace(stdout='2: eth0 inet 10.20.1.10/24',returncode=0)
   if args[0]=='ss':return SimpleNamespace(stdout='MOCK listeners',returncode=0)
   if args[0]=='systemctl':return SimpleNamespace(stdout='inactive' if inactive else 'active',returncode=3 if inactive else 0)
   raise AssertionError(args)
  class Response(io.StringIO):
   status=200
  class Opener:
   def open(self,request,timeout):
    calls.append(request);u=urlparse(request.full_url)
    value={'fixture':'azure-policy-origin-v1','host':request.get_header('Host'),'case_id':request.get_header('X-lab-case-id'),'server_ip':'10.20.1.10','server_port':u.port,'peer_ip':'10.20.1.10',**(changes or {})}
    return Response(json.dumps(value))
  with tempfile.TemporaryDirectory() as temp:
   config=Path(temp)/'config.json';config.write_text(json.dumps({'role':role,'private_ip':'10.20.1.10'}))
   with patch('sys.argv',['ready',str(config)]),patch('subprocess.run',side_effect=process),patch('urllib.request.build_opener',return_value=Opener()),patch('time.sleep'),contextlib.redirect_stdout(io.StringIO()) as out:
    exec(compile(source,'guest-ready-inline','exec'),{})
   return calls,out.getvalue()
 def test_both_names_both_ports_controls(self):
  calls,out=self.run_ready();self.assertEqual(len(calls),4);self.assertIn('LOCAL_FIXTURES_READY',out)
  self.assertEqual({r.get_header('Host') for r in calls},{f'{h}.policy.test:{p}' for h in ['allowed','denied'] for p in [8080,8081]})
 def test_inactive_service_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(inactive=True)
 def test_wrong_role_fails(self):
  with self.assertRaises(AssertionError):self.run_ready(role='app')
 def test_wrong_fixture_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(changes={'fixture':'wrong'})
 def test_wrong_host_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(changes={'host':'other'})
 def test_wrong_case_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(changes={'case_id':'wrong'})
 def test_wrong_peer_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(changes={'peer_ip':'10.0.1.5'})
 def test_wrong_port_fails(self):
  with self.assertRaises(SystemExit):self.run_ready(changes={'server_port':9090})
if __name__=='__main__':unittest.main(verbosity=2)
