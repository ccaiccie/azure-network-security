#!/usr/bin/env python3
"""Test shell control flow with local fake network tools. Does not contact Azure/web."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class GuestHarness(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="harness-", dir=ROOT / "validation"))
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        self.config = self.temp / "config.json"
        self.config.write_text(json.dumps({
            "firewall_private_ip": "10.10.0.4",
            "firewall_public_ip": "198.51.100.80",
            "vm_private_ip": "10.20.1.4",
            "policy_mode": "network",
            "allowed_fqdns": ["www.microsoft.com", "api.ipify.org"],
        }))
        self.env = os.environ.copy()
        self.env.update({
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "EGRESS_DEMO_CONFIG": str(self.config),
        })
        self.make_tool("ip", "#!/bin/sh\necho '2: eth0 inet 10.20.1.4/24 scope global eth0'\n")
        self.make_tool("getent", "#!/bin/sh\necho '203.0.113.10 STREAM example.test'\n")
        self.make_tool("resolvectl", "#!/bin/sh\necho 'Mock DNS Server: 10.10.0.4'\n")
        self.make_tool("dig", "#!/bin/sh\ncase \"$1\" in @168.63.129.16) exit 9;; *) echo 'Mock DNS response';; esac\n")
        self.make_tool("curl", '''#!/usr/bin/env python3
import pathlib, sys
args=sys.argv[1:]
def value(flag): return args[args.index(flag)+1]
url=args[-1]
body=pathlib.Path(value('--output'))
headers=pathlib.Path(value('--dump-header'))
if url.startswith('http:') or 'www.bing.com' in url:
    body.write_text('')
    headers.write_text('')
    print('mock firewall denial', file=sys.stderr)
    print('http_code=000 remote_ip=203.0.113.10 remote_port=80 local_ip=10.20.1.4 local_port=53000')
    raise SystemExit(28)
body.write_text('198.51.100.80' if 'api.ipify.org' in url else 'mock origin body')
headers.write_text('HTTP/1.1 200 OK\\n')
print('http_code=200 remote_ip=203.0.113.10 remote_port=443 local_ip=10.20.1.4 local_port=53000')
''')

    def make_tool(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_harness(self):
        return subprocess.run(
            ['bash', str(ROOT / 'scripts/guest-tests.sh'), str(self.temp / 'evidence')],
            env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30, check=False,
        )

    def tearDown(self):
        shutil.rmtree(self.temp)

    def test_collects_all_cases_without_claiming_pass(self):
        run = self.run_harness()
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertIn('Public-IP observation MATCHES', run.stdout)
        self.assertIn('curl_exit=28', run.stdout)
        self.assertIn('Network FQDN rules allow resolved IPs', run.stdout)
        self.assertIn('No case is declared passed by this script', run.stdout)
        self.assertIn('DNS_BYPASS_VERDICT=NEEDS_REVIEW', run.stdout)
        self.assertIn('DNS CASE direct-platform-tcp', run.stdout)
        self.assertTrue((self.temp / 'evidence/http-negative.stderr').is_file())

    def test_missing_dig_marks_bypass_not_run(self):
        (self.bin / 'dig').unlink()
        # Keep only the harness's required tools, deliberately excluding dig.
        for name in ['bash', 'python3', 'date', 'grep', 'mkdir', 'tee', 'cat', 'sed', 'tail', 'tr']:
            target = shutil.which(name)
            self.assertIsNotNone(target)
            (self.bin / name).symlink_to(target)
        self.env['PATH'] = str(self.bin)
        run = self.run_harness()
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertIn('DNS_BYPASS_VERDICT=NOT_RUN', run.stdout)
        self.assertIn('no DNS-bypass-prevention result can be claimed', run.stdout)

    def test_rejects_wrong_machine(self):
        self.make_tool('ip', "#!/bin/sh\necho '2: eth0 inet 192.0.2.5/24'\n")
        run = self.run_harness()
        self.assertEqual(run.returncode, 2, run.stdout)
        self.assertIn('Run inside the spoke VM', run.stdout)

    def test_rejects_unapproved_positive_host(self):
        self.env['PRIMARY_HOST'] = 'not-allowed.example'
        run = self.run_harness()
        self.assertEqual(run.returncode, 2, run.stdout)
        self.assertIn('not configured', run.stdout)

    def test_application_mode_does_not_report_network_note(self):
        config = json.loads(self.config.read_text())
        config['policy_mode'] = 'application'
        self.config.write_text(json.dumps(config))
        run = self.run_harness()
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertNotIn('Network FQDN rules allow resolved IPs', run.stdout)

if __name__ == '__main__':
    unittest.main(verbosity=2)
