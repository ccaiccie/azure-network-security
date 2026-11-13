#!/usr/bin/env python3
"""Synthetic loopback fixture tests and fake-tool probe tests; no Azure/external traffic."""
import http.client
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ew_fixture", ROOT / "fixtures/server.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.servers = []
        try:
            for port in (8080, 8081):
                server = fixture.make_server("127.0.0.1", port, "db")
                cls.servers.append(server)
                threading.Thread(target=server.serve_forever, daemon=True).start()
        except OSError:
            for server in cls.servers:
                server.shutdown()
                server.server_close()
            raise

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers:
            server.shutdown()
            server.server_close()

    def request(self, port, path="/ready-local", method="GET"):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        connection.request(method, path)
        response = connection.getresponse()
        status, body = response.status, response.read()
        connection.close()
        return status, body

    def test_both_real_loopback_listeners_return_identity(self):
        for port in (8080, 8081):
            status, body = self.request(port)
            record = json.loads(body)
            self.assertEqual(status, 200)
            self.assertEqual(record['server_port'], port)
            self.assertEqual(record['peer_ip'], '127.0.0.1')
            self.assertEqual(record['fixture_role'], 'db')

    def test_c_fixture_role_and_private_source_identity(self):
        server=fixture.make_server('127.0.0.1',0,'c')
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            status,body=self.request(server.server_address[1],'/same-positive-local')
            self.assertEqual(status,200)
            record=json.loads(body)
            self.assertEqual(record['fixture_role'],'c')
            self.assertEqual(record['peer_ip'],'127.0.0.1')
        finally:
            server.shutdown()
            server.server_close()

    def test_never_serves_files(self):
        status, body = self.request(8080, "/../../etc/passwd")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['case'], '/../../etc/passwd')
        self.assertNotIn(b'root:x:', body)

    def test_rejects_overlong_path(self):
        self.assertEqual(self.request(8081, '/' + 'x' * 300)[0], 414)

    def test_rejects_post(self):
        self.assertEqual(self.request(8080, '/test', 'POST')[0], 501)

    def test_ready_script_checks_both_ports(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'validation', prefix='ready-') as name:
            temp = Path(name)
            config = temp / 'config.json'
            config.write_text(json.dumps({'role':'db','private_ip':'127.0.0.1','listen_ports':[8080,8081]}))
            for command, source in {
                'ip': '#!/bin/sh\necho "2: lo inet 127.0.0.1/8"\n',
                'ss': '#!/bin/sh\necho "LISTEN 127.0.0.1:8080 and :8081 (synthetic check output)"\n',
                'systemctl': '#!/bin/sh\necho active\n',
            }.items():
                path = temp / command
                path.write_text(source)
                path.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=f'{temp}:{env["PATH"]}', EW_LAB_CONFIG=str(config))
            run = subprocess.run(['bash',str(ROOT/'scripts/guest-ready.sh')],env=env,text=True,capture_output=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn('LOCAL_FIXTURES_READY',run.stdout)
            self.assertIn('azure-ew-fixture@8081.service',run.stdout)


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(dir=ROOT/'validation',prefix='probe-'))
        self.config = self.temp/'config.json'
        self.config.write_text(json.dumps({'role':'app','private_ip':'10.10.1.10','remote_ip':'10.20.1.10'}))
        for name, content in {
            'ip': '#!/bin/sh\necho "2: eth0 inet 10.10.1.10/24"\n',
            'curl': '''#!/usr/bin/env python3
import json,pathlib,sys
from urllib.parse import urlsplit
args=sys.argv[1:]
assert args[0]=='-q', 'curl must ignore .curlrc'
def value(flag): return args[args.index(flag)+1]
url=urlsplit(args[-1])
body=pathlib.Path(value('--output'))
headers=pathlib.Path(value('--dump-header'))
if url.port==8081:
    body.write_text('');headers.write_text('')
    print('http=000 local=10.10.1.10:53000 remote=10.20.1.10:8081')
    raise SystemExit(28)
record=dict(peer_ip='10.10.1.10',server_ip=url.hostname,server_port=8080,fixture_role='c' if url.hostname=='10.10.2.20' else 'db',case=url.path)
body.write_text(json.dumps(record));headers.write_text('HTTP/1.1 200 OK\\n')
print('http=200 local=10.10.1.10:53000 remote=10.20.1.10:8080')
''',
        }.items():
            path=self.temp/name
            path.write_text(content)
            path.chmod(0o755)
        self.env=os.environ.copy()
        self.env.update(PATH=f'{self.temp}:{self.env["PATH"]}',EW_LAB_CONFIG=str(self.config))

    def tearDown(self):
        shutil.rmtree(self.temp)

    def run_probe(self, case):
        return subprocess.run(['bash',str(ROOT/'scripts/guest-probe.sh'),case,str(self.temp/'evidence')],env=self.env,text=True,capture_output=True,timeout=10)

    def test_positive_checks_identity_but_not_firewall_verdict(self):
        run=self.run_probe('positive')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('FIXTURE_IDENTITY=MATCH',run.stdout)
        self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)

    def test_negative_does_not_claim_firewall_denial(self):
        run=self.run_probe('alternate-port')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('curl_exit=28',run.stdout)
        self.assertIn('Require recent remote listener readiness',run.stdout)

    def enable_same_vnet(self):
        config=json.loads(self.config.read_text())
        config.update(same_vnet_enabled=True,same_vnet_ip='10.10.2.20')
        self.config.write_text(json.dumps(config))

    def test_same_vnet_positive_uses_c_identity(self):
        self.enable_same_vnet()
        run=self.run_probe('same-positive')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('target=10.10.2.20:8080',run.stdout)
        self.assertIn('FIXTURE_IDENTITY=MATCH',run.stdout)

    def test_same_vnet_alternate_port_requires_review(self):
        self.enable_same_vnet()
        run=self.run_probe('same-alternate-port')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('target=10.10.2.20:8081',run.stdout)
        self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)

    def test_same_vnet_is_rejected_when_disabled(self):
        run=self.run_probe('same-positive')
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertIn('not enabled',run.stderr)

    def test_same_vnet_reverse_requires_c(self):
        self.enable_same_vnet()
        run=self.run_probe('same-reverse-new')
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertIn('Wrong role',run.stderr)

    def test_same_vnet_reverse_records_negative_on_c(self):
        self.config.write_text(json.dumps({'role':'c','private_ip':'10.10.2.20',
            'remote_ip':'10.10.1.10','same_vnet_enabled':True,'same_vnet_ip':'10.10.2.20'}))
        (self.temp/'ip').write_text('#!/bin/sh\necho "2: eth0 inet 10.10.2.20/24"\n')
        (self.temp/'curl').write_text('#!/bin/sh\necho "http=000 local=10.10.2.20:53000 remote=10.10.1.10:8080"\nexit 28\n')
        run=self.run_probe('same-reverse-new')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('source_role=c target=10.10.1.10:8080',run.stdout)
        self.assertIn('curl_exit=28',run.stdout)
        self.assertIn('RESULT=NEEDS_REVIEW',run.stdout)
        self.assertIn('Require recent remote listener readiness',run.stdout)

    def test_wrong_role_is_rejected(self):
        run=self.run_probe('reverse-new')
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertIn('Wrong role',run.stderr)

    def test_wrong_machine_is_rejected(self):
        (self.temp/'ip').write_text('#!/bin/sh\necho "2: eth0 inet 192.0.2.2/24"\n')
        run=self.run_probe('positive')
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertIn('Wrong machine',run.stderr)


class CollectorTests(unittest.TestCase):
    def collect_with_fake_tools(self, include_c):
        with tempfile.TemporaryDirectory(dir=ROOT/'validation',prefix='collector-') as name:
            temp=Path(name)
            roles={'app':{'vnet_name':'app','subnet_name':'workload'},
                   'db':{'vnet_name':'db','subnet_name':'workload'}}
            if include_c:
                roles['c']={'vnet_name':'app','subnet_name':'same-vnet'}
            outputs={'resource_group_name':{'value':'inspection-east-west'},
                     'firewall_id':{'value':'/subscriptions/test-sub/resourceGroups/inspection-east-west/providers/Microsoft.Network/azureFirewalls/lab-firewall'},
                     'workloads':{'value':roles}}
            (temp/'outputs.json').write_text(json.dumps(outputs))
            for command,body in {
                'terraform':'#!/usr/bin/env python3\nimport os,pathlib\nprint(pathlib.Path(os.environ["TEST_OUTPUTS"]).read_text())\n',
                'az':'#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["TEST_CALL_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("{}")\n',
            }.items():
                path=temp/command
                path.write_text(body)
                path.chmod(0o755)
            env=os.environ.copy()
            env.update(PATH=f'{temp}:{env["PATH"]}',TEST_OUTPUTS=str(temp/'outputs.json'),TEST_CALL_LOG=str(temp/'calls.jsonl'))
            run=subprocess.run(['bash',str(ROOT/'scripts/collect-control-plane.sh'),str(temp/'evidence')],
                env=env,text=True,capture_output=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            calls=[json.loads(line) for line in (temp/'calls.jsonl').read_text().splitlines()]
            self.assertTrue(all(call[-2:]==['--subscription','test-sub'] for call in calls))
            self.assertFalse(any(word in call for call in calls for word in ['create','update','delete','set','invoke']))
            return calls

    def test_collector_baseline_has_only_two_workloads(self):
        calls=self.collect_with_fake_tools(False)
        self.assertEqual(sum(call[:3]==['network','nic','show-effective-route-table'] for call in calls),2)
        self.assertFalse(any('c-nic' in call or 'c-inspect' in call for call in calls))

    def test_collector_c_uses_existing_app_vnet(self):
        calls=self.collect_with_fake_tools(True)
        self.assertEqual(sum(call[:3]==['network','nic','show-effective-route-table'] for call in calls),3)
        c_subnet=[call for call in calls if call[:4]==['network','vnet','subnet','show'] and 'same-vnet' in call]
        self.assertEqual(len(c_subnet),1)
        self.assertEqual(c_subnet[0][c_subnet[0].index('--vnet-name')+1],'app')
        self.assertTrue(any('c-inspect' in call for call in calls))


if __name__ == '__main__':
    unittest.main(verbosity=2)
