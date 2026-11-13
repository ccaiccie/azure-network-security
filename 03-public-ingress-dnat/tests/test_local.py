#!/usr/bin/env python3
"""Loopback fixtures and fake-command clients/collector only; no Azure/external traffic."""
import http.client
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('dnat_fixture',ROOT/'fixtures/server.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)

class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=fixture.make_server('127.0.0.1',8080,'backend')
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown();cls.server.server_close()
    def request(self,path='/ready-local',method='GET',headers=None):
        conn=http.client.HTTPConnection('127.0.0.1',8080,timeout=3)
        conn.request(method,path,headers=headers or {})
        response=conn.getresponse();status,body=response.status,response.read();conn.close()
        return status,body
    def test_real_loopback_identity(self):
        status,body=self.request();record=json.loads(body)
        self.assertEqual(status,200)
        self.assertEqual(record['fixture_role'],'backend')
        self.assertEqual(record['server_ip'],'127.0.0.1')
        self.assertEqual(record['peer_ip'],'127.0.0.1')
        self.assertEqual(record['server_port'],8080)
    def test_xff_cannot_override_peer_identity(self):
        status,body=self.request(headers={'X-Forwarded-For':'9.9.9.9'})
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)['peer_ip'],'127.0.0.1')
        self.assertNotIn(b'9.9.9.9',body)
    def test_never_serves_files(self):
        status,body=self.request('/../../etc/passwd')
        self.assertEqual(status,200);self.assertNotIn(b'root:x:',body)
        self.assertEqual(json.loads(body)['case'],'/../../etc/passwd')
    def test_rejects_long_path(self): self.assertEqual(self.request('/'+'x'*300)[0],414)
    def test_rejects_post(self): self.assertEqual(self.request('/test','POST')[0],501)
    def readiness(self,active=True,address='127.0.0.1'):
        with tempfile.TemporaryDirectory(dir=ROOT/'validation',prefix='ready-') as name:
            temp=Path(name)
            (temp/'config.json').write_text(json.dumps({'role':'backend','private_ip':address,'port':8080}))
            for tool,body in {
                'ip':'#!/bin/sh\necho "2: lo inet 127.0.0.1/8"\n',
                'ss':'#!/bin/sh\necho "LISTEN 127.0.0.1:8080 (synthetic socket output)"\n',
                'systemctl':'#!/bin/sh\necho '+('active\nexit 0\n' if active else 'inactive\nexit 3\n')
            }.items():
                p=temp/tool;p.write_text(body);p.chmod(0o755)
            env=os.environ.copy();env.update(PATH=f'{temp}:{env["PATH"]}',DNAT_LAB_CONFIG=str(temp/'config.json'))
            return subprocess.run(['bash',str(ROOT/'scripts/guest-ready.sh')],env=env,text=True,capture_output=True,timeout=10)
    def test_ready_uses_local_real_response(self):
        run=self.readiness();self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('LOCAL_FIXTURE_READY',run.stdout)
    def test_ready_rejects_inactive_owned_service(self):
        run=self.readiness(active=False);self.assertNotEqual(run.returncode,0)
        self.assertIn('not active',run.stderr)
    def test_ready_rejects_wrong_machine(self):
        run=self.readiness(address='10.20.1.10');self.assertNotEqual(run.returncode,0)
        self.assertIn('Wrong backend machine',run.stderr)

class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp=Path(tempfile.mkdtemp(dir=ROOT/'validation',prefix='probe-'))
        fake='''#!/usr/bin/env python3
import json,os,pathlib,sys
from urllib.parse import urlsplit
args=sys.argv[1:]
assert args[0]=='-q'
assert '--noproxy' in args and args[args.index('--noproxy')+1]=='*'
assert '--location' not in args and '--insecure' not in args
pathlib.Path(os.environ['TEST_CURL_ARGS']).write_text(json.dumps(args))
def value(flag):return args[args.index(flag)+1]
url=urlsplit(args[-1]);assert url.scheme=='http'
body=pathlib.Path(value('--output'));headers=pathlib.Path(value('--dump-header'))
if url.port==8444 or os.environ.get('TEST_NEGATIVE')=='1':
    body.write_text('');headers.write_text('')
    print('http=000 local=192.0.2.25:54000 remote='+url.hostname+':'+str(url.port))
    raise SystemExit(28)
record=dict(fixture_role='backend',server_ip='10.20.1.10',server_port=8080,
            peer_ip=os.environ.get('TEST_PEER','10.0.1.7'),peer_port=52000,case=url.path)
body.write_text(json.dumps(record));headers.write_text('HTTP/1.1 200 OK\\n')
print('http='+os.environ.get('TEST_HTTP_STATUS','200')+' local=192.0.2.25:54000 remote='+url.hostname+':'+str(url.port))
'''
        p=self.temp/'curl';p.write_text(fake);p.chmod(0o755)
        self.env=os.environ.copy();self.env.update(PATH=f'{self.temp}:{self.env["PATH"]}',TEST_CURL_ARGS=str(self.temp/'args.json'))
    def tearDown(self): shutil.rmtree(self.temp)
    def probe(self,case='positive',p='20.30.40.50',allowed='9.9.9.9/32',source='9.9.9.9'):
        return subprocess.run(['bash',str(ROOT/'scripts/client-probe.sh'),case,p,allowed,source,str(self.temp/'evidence')],
            env=self.env,text=True,capture_output=True,timeout=10)
    def test_positive_recognizes_instance_source_not_client(self):
        run=self.probe();self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('TRANSLATED_FIXTURE_IDENTITY=MATCH',run.stdout)
        self.assertIn('10.0.1.7',run.stdout)
        self.assertIn('NOT independently verified',run.stdout)
        self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)
    def test_public_client_source_at_backend_is_mismatch(self):
        self.env['TEST_PEER']='9.9.9.9';run=self.probe()
        self.assertIn('TRANSLATED_FIXTURE_IDENTITY=MISMATCH',run.stdout)
    def test_non_200_status_cannot_be_positive_identity_match(self):
        self.env['TEST_HTTP_STATUS']='404';run=self.probe()
        self.assertIn('TRANSLATED_FIXTURE_IDENTITY=MISMATCH',run.stdout)
    def test_unpublished_port_targets_8444(self):
        run=self.probe('unpublished-port');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('target=20.30.40.50:8444',run.stdout)
        self.assertIn('curl_exit=28',run.stdout)
        self.assertIn('No NAT Deny is expected',run.stdout)
    def test_excluded_source_requires_different_public_ip(self):
        run=self.probe('excluded-source');self.assertEqual(run.returncode,1)
        self.assertFalse((self.temp/'args.json').exists())
    def test_excluded_source_records_negative_without_verdict(self):
        self.env['TEST_NEGATIVE']='1';run=self.probe('excluded-source',source='8.8.8.8')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('declared_public_source=8.8.8.8',run.stdout)
        self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)
    def test_withdrawal_uses_fresh_public_8443(self):
        self.env['TEST_NEGATIVE']='1';run=self.probe('publication-withdrawn')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('target=20.30.40.50:8443',run.stdout)
    def test_listener_and_blackhole_failures_are_not_policy_verdicts(self):
        self.env['TEST_NEGATIVE']='1'
        for case in ('listener-unavailable','return-blackhole'):
            run=self.probe(case)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)
    def test_rejects_documentation_target_before_curl(self):
        run=self.probe(p='203.0.113.10');self.assertEqual(run.returncode,1)
        self.assertFalse((self.temp/'args.json').exists())
    def test_rejects_broad_allowed_source(self):
        run=self.probe(allowed='9.9.9.0/24');self.assertEqual(run.returncode,1)
        self.assertFalse((self.temp/'args.json').exists())
    def test_rejects_private_declared_client(self):
        run=self.probe(source='10.1.1.1');self.assertEqual(run.returncode,1)
        self.assertFalse((self.temp/'args.json').exists())

class CollectorTests(unittest.TestCase):
    def test_read_only_collector_captures_unpublished_group_and_hub_subnets(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'validation',prefix='collector-') as name:
            temp=Path(name)
            outputs={'resource_group_name':{'value':'inspection-dnat'},'firewall_id':{'value':'/subscriptions/test-sub/resourceGroups/inspection-dnat/providers/Microsoft.Network/azureFirewalls/lab-firewall'}}
            (temp/'outputs.json').write_text(json.dumps(outputs))
            for tool,body in {
                'terraform':'#!/usr/bin/env python3\nimport pathlib,os\nprint(pathlib.Path(os.environ["TEST_OUTPUTS"]).read_text())\n',
                'az':'#!/usr/bin/env python3\nimport os,json,sys\nassert os.environ.get("AZURE_EXTENSION_USE_DYNAMIC_INSTALL")=="no"\nwith open(os.environ["TEST_CALLS"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("[]")\n'
            }.items():
                p=temp/tool;p.write_text(body);p.chmod(0o755)
            env=os.environ.copy();env.update(PATH=f'{temp}:{env["PATH"]}',TEST_OUTPUTS=str(temp/'outputs.json'),TEST_CALLS=str(temp/'calls.jsonl'))
            run=subprocess.run(['bash',str(ROOT/'scripts/collect-control-plane.sh'),str(temp/'evidence')],env=env,text=True,capture_output=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            calls=[json.loads(line) for line in (temp/'calls.jsonl').read_text().splitlines()]
            self.assertTrue(all(c[-2:]==['--subscription','test-sub'] for c in calls if c[0]!='extension'))
            self.assertTrue(any(c[:4]==['extension','show','--name','azure-firewall'] for c in calls))
            self.assertFalse(any(word in c for c in calls for word in ('create','update','delete','invoke','set')))
            self.assertTrue(any(c[:5]==['network','firewall','policy','rule-collection-group','list'] for c in calls))
            self.assertTrue(any('AzureFirewallSubnet' in c for c in calls))
            self.assertTrue(any('AzureBastionSubnet' in c for c in calls))
            self.assertEqual(sum(c[:3]==['network','nic','show-effective-route-table'] for c in calls),1)

class RunbookTests(unittest.TestCase):
    def test_manual_cli_resources_are_subscription_scoped(self):
        commands=[line for line in (ROOT/'README.md').read_text().splitlines()
                  if line.startswith('az ') and not line.startswith('az extension ')]
        self.assertGreater(len(commands),0)
        self.assertTrue(all('--subscription "$SUBSCRIPTION_ID"' in line for line in commands))

    def run_listener_block(self,mode='',stdin='\n'):
        blocks=re.findall(r'```bash\n(.*?)```',(ROOT/'README.md').read_text(),re.S)
        code=next(block for block in blocks if '# Controlled listener contrast:' in block)
        with tempfile.TemporaryDirectory(dir=ROOT/'validation',prefix='runbook-') as name:
            temp=Path(name);(temp/'state').write_text('active')
            fake='''#!/usr/bin/env python3
import json,os,pathlib,sys
root=pathlib.Path(os.environ['TEST_RUNBOOK_ROOT']);args=sys.argv[1:]
with (root/'calls').open('a') as f:f.write(json.dumps(args)+'\\n')
mode=os.environ.get('TEST_RUNBOOK_MODE','')
if args==['/usr/local/bin/dnat-ready']:
    if mode=='not-ready':raise SystemExit(1)
    assert (root/'state').read_text()=='active'
    raise SystemExit(0)
assert args[0]=='systemctl' and args[-1]=='azure-dnat-fixture.service',args
if args[1]=='stop':
    (root/'state').write_text('inactive')
    raise SystemExit(1 if mode=='stop-fails' else 0)
if args[1]=='is-active':raise SystemExit(0 if (root/'state').read_text()=='active' else 3)
if args[1]=='start':
    if mode=='restore-fails':raise SystemExit(1)
    (root/'state').write_text('active');raise SystemExit(0)
raise SystemExit('Unexpected command')
'''
            p=temp/'sudo';p.write_text(fake);p.chmod(0o755)
            env=os.environ.copy();env.update(PATH=f'{temp}:{env["PATH"]}',TEST_RUNBOOK_ROOT=str(temp),TEST_RUNBOOK_MODE=mode)
            run=subprocess.run(['bash','-e','-c',code],input=stdin,env=env,text=True,capture_output=True,timeout=10)
            calls=[json.loads(line) for line in (temp/'calls').read_text().splitlines()]
            return run,calls,(temp/'state').read_text()

    def test_inactive_status_under_errexit_still_restores(self):
        run,calls,state=self.run_listener_block()
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual(state,'active')
        self.assertIn(['systemctl','start','azure-dnat-fixture.service'],calls)
        self.assertIn('restored and locally ready',run.stdout)
    def test_stop_failure_still_restores(self):
        run,calls,state=self.run_listener_block('stop-fails')
        self.assertNotEqual(run.returncode,0)
        self.assertEqual(state,'active')
        self.assertIn(['systemctl','start','azure-dnat-fixture.service'],calls)
    def test_eof_still_restores(self):
        run,calls,state=self.run_listener_block(stdin='')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual(state,'active')
        self.assertIn('Contrast window ended',run.stdout)
    def test_not_ready_does_not_stop_service(self):
        run,calls,state=self.run_listener_block('not-ready')
        self.assertNotEqual(run.returncode,0)
        self.assertEqual(calls,[['/usr/local/bin/dnat-ready']])
        self.assertEqual(state,'active')
    def test_restore_failure_is_reported_not_hidden(self):
        run,calls,state=self.run_listener_block('restore-fails')
        self.assertNotEqual(run.returncode,0)
        self.assertEqual(state,'inactive')
        self.assertIn('manual recovery required',run.stderr)

if __name__=='__main__': unittest.main(verbosity=2)
