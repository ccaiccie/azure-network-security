#!/usr/bin/env python3
"""Offline harness: fake curl/OpenSSL/Azure/Terraform; no TLS/key/cloud operation."""
import json,os,subprocess,tempfile,unittest,zipfile,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1]
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name;a=sys.argv[1:]
log=Path(os.environ['MOCK_LOG'])
with log.open('a') as f:f.write(json.dumps({'cmd':name,'args':a})+'\n')
if name=='ip':print('2: eth0 inet '+os.environ.get('MOCK_IP','10.10.1.10')+'/24 scope global');sys.exit()
if name=='getent':print('192.0.2.50 STREAM mock.azurewebsites.net');sys.exit()
if name=='resolvectl':print('MOCK ONLY DNS F=10.0.1.4');sys.exit()
if name=='terraform':print(Path(os.environ['MOCK_TF']).read_text());sys.exit()
if name=='az':print('{}');sys.exit()
if name=='openssl':
 if a[0]=='version':print('OpenSSL 3.0.0 MOCK');sys.exit()
 if a[0]=='x509':print('MOCK PUBLIC CERT METADATA');sys.exit(int(os.environ.get('MOCK_CERT_RC','0')))
 if a[0]=='s_client':
  print('MOCK handshake, no real certificate or network');sys.exit(int(os.environ.get('MOCK_CHAIN_RC','0')))
if name=='curl':
 if a==['-V']:print('curl 0.0 MOCK '+os.environ.get('MOCK_BACKEND','OpenSSL/3.0.0'));sys.exit()
 assert a[0]=='-q',a
 out=Path(a[a.index('--output')+1]);headers=Path(a[a.index('--dump-header')+1]);url=a[-1]
 case=a[a.index('--header')+1].split(': ',1)[1];path='/'+url.rsplit('/',1)[1]
 out.write_text(json.dumps({'fixture':os.environ.get('MOCK_FIXTURE','azure-tls-origin-v1'),'path':path,'case_id':case}));headers.write_text('HTTP/1.1 '+os.environ.get('MOCK_HTTP','200')+' MOCK\n')
 text='http='+os.environ.get('MOCK_HTTP','200')+' verify='+os.environ.get('MOCK_VERIFY','0')
 if 'local=' in a[a.index('--write-out')+1]:text+=' local=10.10.1.10:43210 remote=192.0.2.50:443 seconds=0.001'
 print(text);sys.exit(int(os.environ.get('MOCK_CURL_RC','0')))
raise SystemExit('Unexpected fake tool invocation '+name+' '+repr(a))
'''
class HelperTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name);self.bin=self.p/'bin';self.bin.mkdir()
  for name in ['curl','openssl','ip','getent','resolvectl','terraform','az']:
   f=self.bin/name;f.write_text(FAKE);f.chmod(0o755)
  self.ca=self.p/'public.pem';self.ca.write_text('-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----\n') # Dummy text accepted only by fake OpenSSL.
  self.cfg=self.p/'config.json';self.cfg.write_text(json.dumps({'app_ip':'10.10.1.10','firewall_ip':'10.0.1.4','origin_host':'mock.azurewebsites.net'}))
  self.log=self.p/'calls.jsonl';self.tf=self.p/'outputs.json'
  sub='11111111-1111-1111-1111-111111111111';vals={'deployment_enabled':True,'firewall_id':f'/subscriptions/{sub}/resourceGroups/mock/providers/Microsoft.Network/azureFirewalls/lab-firewall','resource_group_name':'mock','origin_name':'mock-origin','origin_hostname':'mock.azurewebsites.net'}
  self.tf.write_text(json.dumps({k:{'value':v} for k,v in vals.items()}))
  self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'TLS_LAB_CONFIG':str(self.cfg),'TLS_CA_CHECKER':str(R/'scripts/public-ca-check.py'),'MOCK_LOG':str(self.log),'MOCK_TF':str(self.tf),'SUBSCRIPTION_ID':sub,'HOME':str(self.p)}
 def tearDown(self):self.tmp.cleanup()
 def run_script(self,name,*args,extra=None):
  return subprocess.run(['bash',str(R/'scripts'/name),*map(str,args)],env={**self.env,**(extra or {})},cwd=R,capture_output=True,text=True)
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
 def probe(self,case,extra=None,pin=None):
  args=[case,self.ca,self.p/'result']
  if pin:args.append(pin)
  return self.run_script('guest-probe.sh',*args,extra=extra)
 def curl_request(self):return next(c['args'] for c in self.calls() if c['cmd']=='curl' and c['args']!=['-V'])
 def test_allowed_records_identity_not_final_verdict(self):
  r=self.probe('allowed');self.assertEqual(r.returncode,0,r.stderr);self.assertIn('ORIGIN_IDENTITY=MATCH',r.stdout);self.assertIn('RESULT=NEEDS_REVIEW',r.stdout)
 def test_all_trust_and_network_flags(self):
  self.probe('allowed');a=self.curl_request();self.assertEqual(a[0],'-q')
  for f in ['-4','--http1.1','--tlsv1.2','--tls-max','--cacert','--capath','--noproxy','--proxy','--connect-timeout','--max-time']:self.assertIn(f,a)
  for f in ['-k','--insecure','--location','-L']:self.assertNotIn(f,a)
  self.assertFalse(Path(a[a.index('--capath')+1]).exists(),'Temporary empty trust directory should be removed')
 def test_case_user_agent_matches_header(self):
  self.probe('allowed');a=self.curl_request();case=a[a.index('--header')+1].split(': ',1)[1]
  self.assertEqual(a[a.index('--user-agent')+1],'azure-tls-lab/'+case)
 def test_blocked_exact_url_preserved(self):
  r=self.probe('blocked',{'MOCK_HTTP':'403'});self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.curl_request()[-1],'https://mock.azurewebsites.net/blocked');self.assertIn('NEEDS_REVIEW',r.stdout)
 def test_untrusted_exit_recorded_not_false_pass(self):
  r=self.probe('untrusted',{'MOCK_CURL_RC':'60','MOCK_VERIFY':'20','MOCK_HTTP':'000'});self.assertEqual(r.returncode,0);self.assertIn('curl_exit=60',r.stdout);self.assertNotIn('IDENTITY=MATCH',r.stdout)
 def test_pin_forwarded_and_failure_recorded(self):
  pin='sha256//'+'A'*43+'=';r=self.probe('origin-pin',{'MOCK_CURL_RC':'90'},pin);self.assertIn('curl_exit=90',r.stdout);a=self.curl_request();self.assertEqual(a[a.index('--pinnedpubkey')+1],pin)
 def test_pin_missing_refuses(self):
  r=self.probe('origin-pin');self.assertNotEqual(r.returncode,0);self.assertFalse(any(x['cmd']=='curl' and x['args']!=['-V'] for x in self.calls()))
 def test_wrong_vm_refuses(self):
  r=self.probe('allowed',{'MOCK_IP':'10.10.1.11'});self.assertNotEqual(r.returncode,0)
 def test_non_openssl_curl_refuses(self):
  r=self.probe('allowed',{'MOCK_BACKEND':'Schannel'});self.assertNotEqual(r.returncode,0)
 def test_invalid_host_refuses(self):
  self.cfg.write_text(json.dumps({'app_ip':'10.10.1.10','firewall_ip':'10.0.1.4','origin_host':'attacker.invalid'}));self.assertNotEqual(self.probe('allowed').returncode,0)
 def test_mismatched_origin_detected(self):
  r=self.probe('allowed',{'MOCK_FIXTURE':'wrong'});self.assertIn('ORIGIN_IDENTITY=MISMATCH',r.stdout)
 def test_private_material_marker_refused_before_tls(self):
  self.ca.write_text('NOT A CERTIFICATE: PRIVATE '+'KEY');r=self.probe('allowed');self.assertNotEqual(r.returncode,0);self.assertFalse(any(x['cmd']=='curl' for x in self.calls()))
 def test_pfx_extension_refused(self):
  self.ca=self.ca.rename(self.p/'not-real.pfx');self.assertNotEqual(self.probe('allowed').returncode,0)
 def test_certificate_parse_failure_refused(self):
  self.assertNotEqual(self.probe('allowed',{'MOCK_CERT_RC':'1'}).returncode,0)
 def test_chain_verified_separately(self):
  r=self.run_script('capture-chain.sh',self.ca,self.p/'chain');self.assertEqual(r.returncode,0,r.stderr);self.assertIn('separate_connection=true',r.stdout)
  a=next(c['args'] for c in self.calls() if c['cmd']=='openssl' and c['args'][0]=='s_client')
  for x in ['-verify_hostname','-verify_return_error','-no-CApath','-no-CAstore','-tls1_2']:self.assertIn(x,a)
 def test_chain_failure_propagates(self):
  r=self.run_script('capture-chain.sh',self.ca,self.p/'chain',extra={'MOCK_CHAIN_RC':'1'});self.assertEqual(r.returncode,1)
 def test_origin_preflight_two_real_fixture_paths(self):
  r=self.run_script('origin-preflight.sh',self.ca,self.p/'preflight');self.assertEqual(r.returncode,0,r.stderr)
  urls=[c['args'][-1] for c in self.calls() if c['cmd']=='curl' and c['args']!=['-V']];self.assertEqual(urls,['https://mock.azurewebsites.net/allowed','https://mock.azurewebsites.net/blocked'])
 def test_origin_preflight_rejects_wrong_body(self):
  r=self.run_script('origin-preflight.sh',self.ca,self.p/'preflight',extra={'MOCK_FIXTURE':'welcome-page'});self.assertNotEqual(r.returncode,0)
 def test_origin_preflight_rejects_non_200(self):
  r=self.run_script('origin-preflight.sh',self.ca,self.p/'preflight',extra={'MOCK_HTTP':'403'});self.assertNotEqual(r.returncode,0)
 def test_collector_every_resource_call_scoped(self):
  r=self.run_script('collect-control-plane.sh',self.p/'evidence');self.assertEqual(r.returncode,0,r.stderr)
  calls=[c['args'] for c in self.calls() if c['cmd']=='az'];self.assertGreater(len(calls),10)
  for a in calls:
   if a[:2]==['extension','show']:continue
   self.assertIn('--subscription',a);self.assertEqual(a[a.index('--subscription')+1],self.env['SUBSCRIPTION_ID'])
   self.assertFalse(any(x in a for x in ['create','update','delete','deploy','set','download','assign']))
 def test_wrong_subscription_refuses_before_azure(self):
  r=self.run_script('collect-control-plane.sh',self.p/'evidence',extra={'SUBSCRIPTION_ID':'22222222-2222-2222-2222-222222222222'});self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_deployment_helper_requires_explicit_intent(self):
  r=self.run_script('deploy-origin.sh');self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_deployment_refuses_missing_reviewed_hash(self):
  r=self.run_script('deploy-origin.sh','--confirm-synthetic-origin-upload');self.assertNotEqual(r.returncode,0);self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_deployment_refuses_package_drift(self):
  r=self.run_script('deploy-origin.sh','--confirm-synthetic-origin-upload','0'*64);self.assertNotEqual(r.returncode,0);self.assertIn('differs from reviewed SHA256',r.stderr);self.assertFalse(any(c['cmd']=='az' for c in self.calls()))
 def test_approved_hash_upload_target_mock_only(self):
  subprocess.run(['python3',str(R/'scripts/build-origin.py')],check=True,capture_output=True)
  digest=hashlib.sha256((R/'build/origin.zip').read_bytes()).hexdigest()
  r=self.run_script('deploy-origin.sh','--confirm-synthetic-origin-upload',digest);self.assertEqual(r.returncode,0,r.stderr)
  a=next(c['args'] for c in self.calls() if c['cmd']=='az');self.assertEqual(a[:2],['webapp','deploy']);self.assertEqual(a[a.index('--name')+1],'mock-origin')
  self.assertEqual(a[a.index('--subscription')+1],self.env['SUBSCRIPTION_ID']);self.assertFalse(Path(a[a.index('--src-path')+1]).exists(),'Reviewed temp snapshot should be cleaned after fake upload')
 def test_zip_only_original_source_deterministic(self):
  subprocess.run(['python3',str(R/'scripts/build-origin.py')],check=True,capture_output=True)
  path=R/'build/origin.zip';before=hashlib.sha256(path.read_bytes()).hexdigest()
  subprocess.run(['python3',str(R/'scripts/build-origin.py')],check=True,capture_output=True)
  self.assertEqual(before,hashlib.sha256(path.read_bytes()).hexdigest())
  with zipfile.ZipFile(path) as z:self.assertEqual(set(z.namelist()),{'server.js','package.json'})
if __name__=='__main__':unittest.main(verbosity=2)
