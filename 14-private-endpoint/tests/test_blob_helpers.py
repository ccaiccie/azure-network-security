"""Offline safety/contract tests for guest/probe.py, using stdlib unittest only.

NO LIVE OPERATIONS: socket creation/DNS, HTTP, TLS and subprocess entry points
are default-deny and are replaced only by explicitly controlled fakes. IMDS
responses contain conspicuous fabricated sentinel strings, never credentials.
Nothing here contacts Azure, fetches identity material, or provisions resources.

IMPORTANT LIMIT: mocked TLS checks configuration and control flow only. It does
not establish real certificate trust, hostname matching, expiry/revocation,
chain validation, a real handshake, network routing, or Firewall inspection.
Those claims require separately authorized real-world evidence.

Run: python3 -m unittest discover -s tests -p 'test_blob_helpers.py' -v
"""
import contextlib
import hashlib
import http.client
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import socket
import ssl
import stat
import subprocess
import tempfile
import types
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / 'guest' / 'probe.py'


def forbidden(*args, **kwargs):
    raise AssertionError('A live network, TLS, DNS or subprocess operation was attempted')


# Also deny import-time side effects if the helper gains top-level operations.
spec = importlib.util.spec_from_file_location('azure_pe_lab_probe_under_test', SOURCE)
probe = importlib.util.module_from_spec(spec)
with contextlib.ExitStack() as import_guards:
    for target, names in [(socket, ('socket', 'socketpair', 'create_connection', 'getaddrinfo',
                                    'gethostbyname', 'gethostbyname_ex', 'gethostbyaddr')),
                          (ssl, ('create_default_context', 'SSLContext')),
                          (subprocess, ('run', 'Popen', 'call', 'check_call', 'check_output')),
                          (http.client, ('HTTPConnection', 'HTTPSConnection')),
                          (os, ('system', 'popen'))]:
        for name in names:
            import_guards.enter_context(mock.patch.object(target, name, forbidden))
    spec.loader.exec_module(probe)
REAL_DEADLINE = probe.deadline

# This deliberately fabricated value is NOT a credential or a usable token.
FAKE_TOKEN = 'FAKE_TEST_ONLY_TOKEN_NOT_A_CREDENTIAL_000000'
NOW = 1700000000
CASE = '11111111-2222-4333-8444-555555555555'
E = '10.30.1.7'
S = '10.10.1.10'
PORT = 49152


def config(role='reader'):
    return {
        'role': role, 'private_ip': probe.IPS[role],
        'firewall_private_ip': '10.0.1.4', 'endpoint_ip': E,
        'storage_account_name': 'offlinelab123',
        'blob_fqdn': 'offlinelab123.blob.core.windows.net',
        'container': 'lab-data', 'blob_name': 'proof.txt',
    }


class FakeResponse:
    def __init__(self, status=200, body=b'', headers=None):
        self.status = status
        self.body = body
        self.headers = headers or {}
        self.read_sizes = []
        self.requested_headers = []

    def read(self, size):
        self.read_sizes.append(size)
        if isinstance(self.body, BaseException):
            raise self.body
        return self.body[:size]

    def getheader(self, name):
        self.requested_headers.append(name)
        return self.headers.get(name)


class Scenario:
    """Small explicit network simulator. It never wraps a real socket."""
    def __init__(self, test, role='reader', status=200, body=None):
        self.test = test
        self.config = config(role)
        self.events = []
        self.dns_answers = [E]
        self.bound_ip = self.config['private_ip']
        self.bound_port = PORT
        self.peer = (E, 443)
        self.connect_error = None
        self.wrap_error = None
        self.request_error = None
        self.response_error = None
        self.check_hostname = True
        self.verify_mode = probe.ssl.CERT_REQUIRED
        self.raw_sockets = []
        self.contexts = []
        self.connections = []
        self.imds_response = FakeResponse(200, json.dumps({
            'access_token': FAKE_TOKEN, 'token_type': 'Bearer',
            'resource': 'https://storage.azure.com/', 'expires_on': str(NOW + 3600),
        }).encode())
        self.blob_response = FakeResponse(status, probe.PAYLOAD if body is None else body)
        self.http_calls = []
        test.patch(probe.socket, 'getaddrinfo', self.getaddrinfo)
        test.patch(probe.socket, 'socket', self.socket)
        test.patch(probe.ssl, 'create_default_context', self.context)
        test.patch(probe.http.client, 'HTTPConnection', self.http)
        test.patch(probe, 'local_nic', lambda c: 'eth-test')

    def getaddrinfo(self, host, port, **kwargs):
        self.events.append(('dns', host, port, kwargs))
        return [(probe.socket.AF_INET, probe.socket.SOCK_STREAM, 6, '', (a, 443))
                for a in self.dns_answers]

    def socket(self, family, kind):
        self.events.append(('socket', family, kind))
        self.test.assertEqual((family, kind), (probe.socket.AF_INET, probe.socket.SOCK_STREAM))
        raw = FakeSocket(self)
        self.raw_sockets.append(raw)
        return raw

    def context(self, *, cafile):
        self.events.append(('context', cafile))
        ctx = FakeContext(self)
        self.contexts.append(ctx)
        return ctx

    def http(self, host, port, **kwargs):
        self.http_calls.append((host, port, kwargs))
        if host == '169.254.169.254':
            self.events.append(('imds', host, port))
            conn = FakeConnection(self, True)
        else:
            self.test.assertEqual((host, port), (self.config['blob_fqdn'], 443))
            self.events.append(('blob-http', host, port))
            conn = FakeConnection(self, False)
        self.connections.append(conn)
        return conn


class FakeSocket:
    def __init__(self, scenario):
        self.scenario = scenario
        self.closed = False
        self.timeout = None
        self.bound = None
        self.connected = None

    def settimeout(self, seconds):
        self.timeout = seconds

    def bind(self, address):
        self.bound = address
        self.scenario.events.append(('bind', address))

    def getsockname(self):
        return (self.scenario.bound_ip, self.scenario.bound_port)

    def connect(self, address):
        s = self.scenario
        self.connected = address
        s.events.append(('connect', address))
        # Prove the tuple evidence exists before the first connection attempt.
        attempt_path = s.test.out / 'attempt.json'
        s.test.assertTrue(attempt_path.is_file())
        attempt = json.loads(attempt_path.read_text())
        s.test.assertEqual(attempt['attempted_destination'], [E, 443])
        s.test.assertEqual(attempt['attempted_local'], [s.bound_ip, s.bound_port])
        s.test.assertIn('started_utc', attempt)
        if s.connect_error:
            raise s.connect_error

    def getpeername(self):
        return self.scenario.peer

    def close(self):
        self.closed = True
        self.scenario.events.append(('raw-close',))


class FakeTLS:
    def __init__(self, raw):
        self.raw = raw
        self.closed = False

    def version(self):
        return 'TLSv1.3-MOCK-ONLY'

    def getpeercert(self, binary_form=False):
        assert binary_form is True
        return b'FAKE_CERTIFICATE_BYTES_NOT_AN_ACTUAL_CERTIFICATE'

    def getpeername(self):
        return self.raw.getpeername()

    def close(self):
        self.closed = True
        self.raw.close()


class FakeContext:
    def __init__(self, scenario):
        self.scenario = scenario
        self.check_hostname = scenario.check_hostname
        self.verify_mode = scenario.verify_mode
        self.minimum_version = None
        self.tls = None
        self.server_hostname = None

    def wrap_socket(self, raw, *, server_hostname):
        self.server_hostname = server_hostname
        self.scenario.events.append(('wrap', server_hostname))
        if self.scenario.wrap_error:
            raise self.scenario.wrap_error
        self.tls = FakeTLS(raw)
        return self.tls


class FakeConnection:
    def __init__(self, scenario, imds):
        self.scenario = scenario
        self.imds = imds
        self.closed = False
        self.sock = None
        self.auto_open = 1
        self.requests = []
        self.request_headers_reference = None

    def request(self, method, path, body=None, headers=None):
        if not self.imds:
            self.scenario.test.assertEqual(self.auto_open, 0)
            self.scenario.test.assertIsInstance(self.sock, FakeTLS)
        self.requests.append((method, path, body, dict(headers or {})))
        self.request_headers_reference = headers
        self.scenario.events.append(('request-imds' if self.imds else 'request-blob', method, path))
        if not self.imds and self.scenario.request_error:
            raise self.scenario.request_error

    def getresponse(self):
        if not self.imds and self.scenario.response_error:
            raise self.scenario.response_error
        return self.scenario.imds_response if self.imds else self.scenario.blob_response

    def close(self):
        self.closed = True
        if self.sock is not None:
            self.sock.close()


class OfflineCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pe-offline-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.out = self.root / 'evidence'
        self.patch(probe.socket, 'socket', forbidden)
        self.patch(probe.socket, 'socketpair', forbidden)
        self.patch(probe.socket, 'create_connection', forbidden)
        self.patch(probe.socket, 'getaddrinfo', forbidden)
        self.patch(probe.socket, 'gethostbyname', forbidden)
        self.patch(probe.socket, 'gethostbyname_ex', forbidden)
        self.patch(probe.socket, 'gethostbyaddr', forbidden)
        self.patch(probe.ssl, 'create_default_context', forbidden)
        self.patch(probe.ssl, 'SSLContext', forbidden)
        self.patch(probe.http.client, 'HTTPConnection', forbidden)
        self.patch(probe.http.client, 'HTTPSConnection', forbidden)
        if hasattr(probe.ssl, 'wrap_socket'):
            self.patch(probe.ssl, 'wrap_socket', forbidden)
        for name in ('run', 'Popen', 'call', 'check_call', 'check_output'):
            self.patch(probe.subprocess, name, forbidden)
        self.patch(probe.os, 'system', forbidden)
        self.patch(probe.os, 'popen', forbidden)
        self.patch(probe, 'deadline', lambda seconds: contextlib.nullcontext())
        self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW,
                                                     monotonic=mock.Mock(side_effect=[100, 100.125])))
        self.patch(probe.uuid, 'uuid4', lambda: CASE)

    def patch(self, target, name, value):
        p = mock.patch.object(target, name, value)
        self.addCleanup(p.stop)
        return p.start()

    def run_case(self, scenario, mode='read', *, confirm_token=True, confirm_data=False):
        return probe.run_probe(scenario.config, mode, str(self.out), confirm_token, confirm_data)[0]

    def evidence(self):
        return '\n'.join(p.read_text() for p in self.out.iterdir() if p.is_file())

    def assert_all_closed(self, scenario):
        self.assertTrue(all(s.closed for s in scenario.raw_sockets))
        self.assertTrue(all(c.closed for c in scenario.connections))
        self.assertTrue(all(c.tls is None or c.tls.closed for c in scenario.contexts))


class ConfigurationTests(OfflineCase):
    def test_exact_canonical_config_copies_and_accepts_roles(self):
        for role in ('reader', 'seed'):
            c = config(role)
            self.assertEqual(probe.validate_config(c), c)
            self.assertIsNot(probe.validate_config(c), c)
        for value in ('10.0.1.4', '10.0.1.5', '10.0.1.62'):
            c = dict(config(), firewall_private_ip=value)
            self.assertEqual(probe.validate_config(c), c)

    def test_fields_are_exact_and_secret_fields_rejected(self):
        for value in (None, [], '', 3):
            with self.subTest(value=value), self.assertRaises(ValueError):
                probe.validate_config(value)
        for field in probe.FIELDS:
            c = config(); del c[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                probe.validate_config(c)
        for field in ('access_token', 'account_key', 'sas', 'proxy', 'endpoint', 'extra'):
            c = dict(config(), **{field: 'FAKE_ONLY'})
            with self.subTest(extra=field), self.assertRaises(ValueError):
                probe.validate_config(c)

    def test_fixed_role_addresses_and_object_are_immutable(self):
        bad = {'role': ['admin', 'Reader', '', None],
               'private_ip': ['10.10.1.11', '010.10.1.10', '127.0.0.1', S + '/32'],
               'endpoint_ip': ['10.30.1.8', '127.0.0.1', '10.30.1.7/32'],
               'container': ['other', '../lab-data', 'Lab-data'],
               'blob_name': ['other.txt', '../proof.txt', 'proof.txt?sig=fake']}
        for field, values in bad.items():
            for value in values:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    probe.validate_config(dict(config(), **{field: value}))

    def test_hostname_and_account_constraints(self):
        for value in ('aa', 'a' * 25, 'Uppercase123', 'has-hyphen', 'bad/name', '', None, 5):
            c = dict(config(), storage_account_name=value)
            with self.subTest(account=value), self.assertRaises(ValueError):
                probe.validate_config(c)
        for value in ('offlinelab123.privatelink.blob.core.windows.net',
                      'offlinelab123.blob.core.windows.net.',
                      'https://offlinelab123.blob.core.windows.net',
                      'offlinelab123.blob.core.windows.net.evil.invalid', E, None):
            with self.subTest(host=value), self.assertRaises(ValueError):
                probe.validate_config(dict(config(), blob_fqdn=value))
        for value in ('abc', 'a' * 24):
            c = dict(config(), storage_account_name=value, blob_fqdn=value + '.blob.core.windows.net')
            self.assertEqual(probe.validate_config(c), c)

    def test_firewall_must_be_canonical_allocated_ipv4(self):
        for value in ('10.0.1.0', '10.0.1.1', '10.0.1.2', '10.0.1.3', '10.0.1.63',
                      '10.0.1.64', '10.0.2.4', '010.0.1.4', '10.0.1.4/26', ' 10.0.1.4',
                      '::ffff:10.0.1.4', '::1', 167772420, None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                probe.validate_config(dict(config(), firewall_private_ip=value))

    def test_all_mode_role_and_confirmation_guards_precede_output(self):
        cases = [('reader', 'unknown', True, True), ('seed', 'read', True, False),
                 ('reader', 'seed', True, True), ('reader', 'read', False, False),
                 ('seed', 'seed', False, True), ('seed', 'seed', True, False)]
        for role, mode, token, data in cases:
            with self.subTest(role=role, mode=mode, token=token, data=data), self.assertRaises(ValueError):
                probe.run_probe(config(role), mode, self.out, token, data)
            self.assertFalse(self.out.exists())


class OutputTests(OfflineCase):
    def test_new_output_and_files_have_private_modes(self):
        out = probe.new_out(self.out, CASE)
        probe.write_json(out / 'sample.json', {'safe': True})
        self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((out / 'sample.json').stat().st_mode), 0o600)
        self.assertEqual(json.loads((out / 'sample.json').read_text()), {'safe': True})

    def test_existing_directory_and_file_never_clobbered(self):
        self.out.mkdir(); marker = self.out / 'marker'; marker.write_text('unchanged')
        with self.assertRaises(FileExistsError):
            probe.new_out(self.out, CASE)
        with self.assertRaises(FileExistsError):
            probe.write_json(marker, {'overwrite': True})
        self.assertEqual(marker.read_text(), 'unchanged')

    def test_existing_file_cannot_be_output_directory(self):
        self.out.write_text('unchanged')
        with self.assertRaises(FileExistsError):
            probe.new_out(self.out, CASE)
        self.assertEqual(self.out.read_text(), 'unchanged')

    def test_output_symlinks_and_json_symlinks_are_rejected(self):
        target = self.root / 'target'; target.mkdir()
        self.out.symlink_to(target, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            probe.new_out(self.out, CASE)
        self.assertEqual(list(target.iterdir()), [])
        existing = target / 'data.json'; existing.write_text('unchanged')
        for name, dest in [('existing-link', existing), ('dangling-link', target / 'absent')]:
            link = self.root / name; link.symlink_to(dest)
            with self.subTest(name=name), self.assertRaises(FileExistsError):
                probe.write_json(link, {'overwrite': True})
        self.assertEqual(existing.read_text(), 'unchanged')
        self.assertFalse((target / 'absent').exists())

    def test_generated_output_is_unique_and_private(self):
        with mock.patch.object(probe.tempfile, 'tempdir', str(self.root)):
            first = probe.new_out(None, CASE)
            second = probe.new_out(None, CASE)
        self.assertNotEqual(first, second)
        self.assertEqual(stat.S_IMODE(first.stat().st_mode), 0o700)
        self.assertTrue(first.name.startswith('pe-' + CASE + '-'))

    def test_symlink_ancestor_is_rejected_without_creating_output(self):
        target = self.root / 'real-parent'; target.mkdir()
        alias = self.root / 'parent-alias'; alias.symlink_to(target, target_is_directory=True)
        for path in (alias / 'evidence', alias / 'missing' / 'evidence'):
            with self.subTest(path=path), self.assertRaises(FileExistsError):
                probe.new_out(path, CASE)
        self.assertEqual(list(target.iterdir()), [])


class PreflightAndTransportTests(OfflineCase):
    def test_nic_requires_exactly_one_nonloopback_source(self):
        rows = [{'ifname': 'lo', 'addr_info': [{'local': S}]},
                {'ifname': 'eth-test', 'addr_info': [{'local': S}]}]
        runner = mock.Mock(return_value=types.SimpleNamespace(stdout=json.dumps(rows)))
        self.patch(probe.subprocess, 'run', runner)
        self.assertEqual(probe.local_nic(config()), 'eth-test')
        runner.assert_called_once_with(['ip', '-j', '-4', 'addr', 'show'], check=True,
                                       capture_output=True, text=True, timeout=5)
        for rows in ([], [{'ifname': 'lo', 'addr_info': [{'local': S}]}],
                     [{'ifname': 'a', 'addr_info': [{'local': S}]},
                      {'ifname': 'b', 'addr_info': [{'local': S}]}]):
            runner.return_value.stdout = json.dumps(rows)
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                probe.local_nic(config())

    def test_dns_only_endpoint_precedes_literal_connect_and_token(self):
        s = Scenario(self); s.dns_answers = [E, E]
        result = self.run_case(s)
        events = [row[0] for row in s.events]
        self.assertLess(events.index('dns'), events.index('imds'))
        self.assertLess(events.index('dns'), events.index('connect'))
        self.assertEqual(s.events[0], ('dns', s.config['blob_fqdn'], 443,
                                     {'family': probe.socket.AF_INET, 'type': probe.socket.SOCK_STREAM}))
        raw = s.raw_sockets[0]
        self.assertEqual(raw.bound, (S, 0))
        self.assertEqual(raw.connected, (E, 443))
        self.assertEqual(raw.timeout, 5)
        self.assertEqual(result['os_ipv4_answers'], [E])
        self.assert_all_closed(s)

    def test_wrong_or_mixed_dns_never_requests_token_or_creates_socket(self):
        for answers in ([], ['203.0.113.8'], [E, '203.0.113.8'], ['10.30.1.8']):
            with self.subTest(answers=answers):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self); s.dns_answers = answers
                result = self.run_case(s)
                self.assertEqual(result['error_phase'], 'local-preflight')
                self.assertFalse(result['token_requested'])
                self.assertEqual(s.raw_sockets, [])
                self.assertEqual(s.http_calls, [])

    def test_connect_failure_preserves_preconnect_tuple_and_elapsed(self):
        s = Scenario(self); s.connect_error = TimeoutError('malicious ' + FAKE_TOKEN)
        result = self.run_case(s, 'noauth', confirm_token=False)
        attempt = json.loads((self.out / 'attempt.json').read_text())
        self.assertEqual(attempt['attempted_local'], [S, PORT])
        self.assertEqual(attempt['attempted_destination'], [E, 443])
        self.assertEqual(result['elapsed_seconds'], 0.125)
        self.assertIn('started_utc', result); self.assertIn('completed_utc', result)
        self.assertFalse(result['tcp_connect_completed'])
        self.assertEqual(result['error_phase'], 'tcp-connect')
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assert_all_closed(s)

    def test_invalid_bound_tuple_rejected_before_connect(self):
        for ip, port in [('127.0.0.1', PORT), (S, 0), (S, 65536)]:
            with self.subTest(ip=ip, port=port):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self); s.bound_ip = ip; s.bound_port = port
                result = self.run_case(s, 'noauth')
                self.assertEqual(result['error_phase'], 'tcp-connect')
                self.assertIsNone(s.raw_sockets[0].connected)
                self.assert_all_closed(s)

    def test_unexpected_connected_peer_is_rejected_before_tls(self):
        s = Scenario(self); s.peer = ('203.0.113.8', 443)
        result = self.run_case(s, 'noauth')
        self.assertEqual(result['error_phase'], 'tcp-connect')
        self.assertTrue(result['tcp_connect_completed'])
        self.assertEqual(s.contexts, [])
        self.assert_all_closed(s)

    def test_strict_tls_context_ordinary_hostname_and_pinned_ca(self):
        s = Scenario(self)
        result = self.run_case(s)
        ctx = s.contexts[0]
        self.assertIn(('context', probe.CA_BUNDLE), s.events)
        self.assertEqual(ctx.minimum_version, probe.ssl.TLSVersion.TLSv1_2)
        self.assertTrue(ctx.check_hostname)
        self.assertEqual(ctx.verify_mode, probe.ssl.CERT_REQUIRED)
        self.assertEqual(ctx.server_hostname, s.config['blob_fqdn'])
        self.assertTrue(result['tls_verified'])  # Fake-flow flag, NOT real TLS validation.
        self.assertEqual(result['certificate_sha256'], hashlib.sha256(
            b'FAKE_CERTIFICATE_BYTES_NOT_AN_ACTUAL_CERTIFICATE').hexdigest())
        self.assert_all_closed(s)

    def test_insecure_tls_configuration_fails_before_wrap(self):
        for check, verify in [(False, probe.ssl.CERT_REQUIRED), (True, probe.ssl.CERT_NONE)]:
            with self.subTest(check=check, verify=verify):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self); s.check_hostname = check; s.verify_mode = verify
                result = self.run_case(s, 'noauth')
                self.assertEqual(result['error_phase'], 'tls-handshake')
                self.assertFalse(result['tls_verified'])
                self.assertNotIn('wrap', [e[0] for e in s.events])
                self.assert_all_closed(s)

    def test_mock_certificate_failure_is_redacted_and_socket_closed(self):
        s = Scenario(self); s.wrap_error = probe.ssl.SSLCertVerificationError('fake failure ' + FAKE_TOKEN)
        result = self.run_case(s)
        self.assertFalse(result['tls_verified'])
        self.assertEqual(result['error_type'], 'SSLCertVerificationError')
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assert_all_closed(s)

    def test_deadline_signal_handler_and_cleanup_no_real_signals(self):
        # Call the original context manager with fake signal functions only.
        calls = []
        old_handler = object()
        fake_signal = types.SimpleNamespace(SIGALRM=signal.SIGALRM, ITIMER_REAL=signal.ITIMER_REAL,
            getsignal=lambda sig: old_handler,
            signal=lambda sig, handler: calls.append(('handler', sig, handler)),
            setitimer=lambda which, seconds: calls.append(('timer', which, seconds)))
        self.patch(probe, 'signal', fake_signal)
        with self.assertRaisesRegex(TimeoutError, 'bounded operation expired'):
            with REAL_DEADLINE(30):
                calls[0][2](signal.SIGALRM, None)
        self.assertEqual(calls[1], ('timer', signal.ITIMER_REAL, 30))
        self.assertEqual(calls[-2], ('timer', signal.ITIMER_REAL, 0))
        self.assertEqual(calls[-1], ('handler', signal.SIGALRM, old_handler))

    def test_probe_deadline_failure_records_elapsed_and_closes(self):
        s = Scenario(self); s.response_error = TimeoutError('bounded operation expired')
        seen = []
        @contextlib.contextmanager
        def fake_deadline(seconds):
            seen.append(seconds); yield
        self.patch(probe, 'deadline', fake_deadline)
        result = self.run_case(s)
        self.assertEqual(seen, [30])
        self.assertEqual(result['error_type'], 'TimeoutError')
        self.assertEqual(result['elapsed_seconds'], 0.125)
        self.assert_all_closed(s)


class TokenTests(OfflineCase):
    def test_imds_exact_endpoint_audience_headers_source_and_memory_only(self):
        s = Scenario(self)
        token = probe.acquire_token(s.config)
        self.assertEqual(token, FAKE_TOKEN)
        self.assertEqual(s.http_calls, [('169.254.169.254', 80,
                                       {'timeout': 5, 'source_address': (S, 0)})])
        conn = s.connections[0]
        self.assertEqual(conn.requests, [('GET',
            '/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F',
            None, {'Metadata': 'true', 'Connection': 'close'})])
        self.assertEqual(s.imds_response.read_sizes, [32769])
        self.assertTrue(conn.closed)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_imds_non200_redirect_or_error_does_not_read_body_or_retry(self):
        for status in (201, 301, 302, 307, 400, 401, 403, 429, 500):
            with self.subTest(status=status):
                s = Scenario(self); s.imds_response.status = status
                with self.assertRaisesRegex(ValueError, 'did not succeed'):
                    probe.acquire_token(s.config)
                self.assertEqual(s.imds_response.read_sizes, [])
                self.assertEqual(len(s.http_calls), 1)
                self.assertTrue(s.connections[0].closed)

    def test_imds_body_bound_and_parse_failures_close_connection(self):
        for body in (b'x' * 32769, b'not-json', b'[]', b'null', b'{}', b'\xff'):
            with self.subTest(body_length=len(body)):
                s = Scenario(self); s.imds_response.body = body
                with self.assertRaises((ValueError, AttributeError, TypeError)):
                    probe.acquire_token(s.config)
                self.assertEqual(s.imds_response.read_sizes, [32769])
                self.assertTrue(s.connections[0].closed)

    def test_imds_exact_body_limit_is_permitted(self):
        s = Scenario(self)
        envelope = json.loads(s.imds_response.body)
        envelope['unused_padding'] = ''
        raw = json.dumps(envelope).encode()
        envelope['unused_padding'] = 'P' * (32768 - len(raw))
        s.imds_response.body = json.dumps(envelope).encode()
        self.assertEqual(len(s.imds_response.body), 32768)
        self.assertEqual(probe.acquire_token(s.config), FAKE_TOKEN)
        self.assertEqual(s.imds_response.read_sizes, [32769])
        self.assertTrue(s.connections[0].closed)

    def test_token_envelope_rejects_invalid_type_audience_expiry_and_token(self):
        base = {'access_token': FAKE_TOKEN, 'token_type': 'Bearer',
                'resource': 'https://storage.azure.com/', 'expires_on': NOW + 3600}
        cases = [('access_token', None), ('access_token', 123), ('access_token', 'x' * 19),
                 ('access_token', 'x' * 16385), ('access_token', FAKE_TOKEN + '\n'),
                 ('access_token', FAKE_TOKEN + ' '), ('access_token', FAKE_TOKEN + '/'),
                 ('token_type', ''), ('token_type', 'Basic'), ('token_type', None),
                 ('resource', 'https://management.azure.com/'),
                 ('resource', 'https://storage.azure.com'), ('resource', None),
                 ('expires_on', NOW - 1), ('expires_on', NOW + 30),
                 ('expires_on', NOW + 86400), ('expires_on', NOW + 86401),
                 ('expires_on', 'nonsense'), ('expires_on', None)]
        for key, value in cases:
            with self.subTest(field=key, value=repr(value)[:40]):
                s = Scenario(self)
                s.imds_response.body = json.dumps(dict(base, **{key: value})).encode()
                with self.assertRaises((ValueError, TypeError)):
                    probe.acquire_token(s.config)
                self.assertTrue(s.connections[0].closed)
        for key in base:
            with self.subTest(missing=key):
                s = Scenario(self); row = dict(base); del row[key]
                s.imds_response.body = json.dumps(row).encode()
                with self.assertRaises((ValueError, TypeError)):
                    probe.acquire_token(s.config)
                self.assertTrue(s.connections[0].closed)

    def test_token_min_max_lengths_and_safe_expiry_boundaries(self):
        for token, expiry in [('F' * 20, NOW + 31), ('F' * 16384, NOW + 86399)]:
            with self.subTest(token_length=len(token), expiry=expiry):
                s = Scenario(self)
                s.imds_response.body = json.dumps({'access_token': token,
                    'token_type': 'bEaReR', 'resource': 'https://storage.azure.com/',
                    'expires_on': str(expiry)}).encode()
                self.assertEqual(probe.acquire_token(s.config), token)
                self.assertTrue(s.connections[0].closed)

    def test_malicious_token_envelope_errors_are_redacted_in_evidence(self):
        s = Scenario(self)
        s.imds_response.body = json.dumps({'access_token': FAKE_TOKEN,
            'token_type': 'Bearer', 'resource': 'https://storage.azure.com/',
            'expires_on': 'malicious-' + FAKE_TOKEN}).encode()
        result = self.run_case(s)
        self.assertTrue(result['token_requested'])
        self.assertFalse(result['token_acquired'])
        self.assertEqual(result['error_phase'], 'token-acquisition')
        self.assertEqual(s.raw_sockets, [])
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assert_all_closed(s)

    def test_token_and_authorization_never_persisted_on_success(self):
        s = Scenario(self)
        result = self.run_case(s)
        self.assertTrue(result['token_acquired'])
        conn = next(c for c in s.connections if not c.imds)
        self.assertEqual(conn.requests[0][3]['Authorization'], 'Bearer ' + FAKE_TOKEN)
        self.assertNotIn('Authorization', conn.request_headers_reference)
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assertNotIn('Bearer ' + FAKE_TOKEN, json.dumps(result))
        self.assertEqual({p.name for p in self.out.iterdir()},
                         {'runtime-config.json', 'attempt.json', 'result.json'})
        self.assertNotIn('access_token', self.evidence())

    def test_token_echo_in_otherwise_allowed_headers_is_never_persisted(self):
        # These are fabricated sentinel strings, never real identity material.
        cases = [('FAKETESTONLYNEVERACREDENTIAL0123456789',
                  {'x-ms-error-code': 'FailureFAKETESTONLYNEVERACREDENTIAL0123456789',
                   'etag': '"FAKETESTONLYNEVERACREDENTIAL0123456789"'}),
                 ('FADEFADEFADEFADEFADEFADEFADEFADE',
                  {'x-ms-request-id': 'FADEFADEFADEFADEFADEFADEFADEFADE',
                   'x-ms-client-request-id': 'FADEFADEFADEFADEFADEFADEFADEFADE',
                   'x-ms-error-code': 'FADEFADEFADEFADEFADEFADEFADEFADE',
                   'etag': 'FADEFADEFADEFADEFADEFADEFADEFADE'})]
        for fake_token, echoed_headers in cases:
            with self.subTest(header_names=list(echoed_headers)):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self)
                envelope = json.loads(s.imds_response.body)
                envelope['access_token'] = fake_token
                s.imds_response.body = json.dumps(envelope).encode()
                s.blob_response.headers = echoed_headers
                result = self.run_case(s)
                self.assertNotIn(fake_token, self.evidence())
                self.assertEqual(result['service_headers'], {})
                self.assert_all_closed(s)

    def test_request_response_and_interrupt_exceptions_are_redacted(self):
        for field, exc in [('request_error', ValueError('Authorization: Bearer ' + FAKE_TOKEN)),
                           ('response_error', RuntimeError('server echoed ' + FAKE_TOKEN)),
                           ('response_error', KeyboardInterrupt(FAKE_TOKEN)),
                           ('response_error', SystemExit(FAKE_TOKEN))]:
            with self.subTest(field=field, kind=type(exc).__name__):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self); setattr(s, field, exc)
                result = self.run_case(s)
                self.assertEqual(result['error_type'], type(exc).__name__)
                self.assertNotIn(FAKE_TOKEN, self.evidence())
                self.assertFalse(result['authorized_blob_read_proven'])
                conn = next(c for c in s.connections if not c.imds)
                self.assertNotIn('Authorization', conn.request_headers_reference)
                if isinstance(exc, (KeyboardInterrupt, SystemExit)):
                    self.assertTrue(result['interrupted'])
                self.assert_all_closed(s)


class BlobOperationTests(OfflineCase):
    def test_reader_exact_get_headers_body_hash_and_receipt(self):
        s = Scenario(self)
        result = self.run_case(s)
        conn = next(c for c in s.connections if not c.imds)
        method, path, body, headers = conn.requests[0]
        self.assertEqual((method, path, body), ('GET', '/lab-data/proof.txt', None))
        self.assertEqual(headers['Host'], s.config['blob_fqdn'])
        self.assertEqual(headers['x-ms-version'], '2023-11-03')
        self.assertRegex(headers['x-ms-date'],
                         r'^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$')
        self.assertEqual(headers['x-ms-client-request-id'], CASE)
        self.assertEqual(headers['User-Agent'], 'azure-pe-lab/' + CASE)
        self.assertEqual(headers['Connection'], 'close')
        self.assertTrue(result['authorized_blob_read_proven'])
        self.assertFalse(result['synthetic_blob_created'])
        self.assertEqual(result['response_body_sha256'], probe.PAYLOAD_SHA256)
        self.assertEqual(result['response_body_bytes_observed'], len(probe.PAYLOAD))
        self.assertEqual(result['observation'], 'AUTHORIZED_CONTENT_MATCH')
        self.assertFalse(result['private_path_proven'])
        self.assertFalse(result['firewall_inspection_proven'])
        self.assertEqual(result['outcome'], 'NEEDS_REVIEW')
        self.assertEqual(json.loads((self.out / 'result.json').read_text()), result)
        self.assertNotIn(probe.PAYLOAD.decode(), self.evidence())
        self.assert_all_closed(s)

    def test_reader_requires_200_and_exact_fixed_content(self):
        for status, body in [(200, b''), (200, probe.PAYLOAD + b'\n'),
                             (200, probe.PAYLOAD[:-1]), (206, probe.PAYLOAD),
                             (403, probe.PAYLOAD), (404, probe.PAYLOAD)]:
            with self.subTest(status=status, length=len(body)):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self, status=status, body=body)
                result = self.run_case(s)
                self.assertFalse(result['authorized_blob_read_proven'])
                self.assertFalse(result['private_path_proven'])
                self.assertFalse(result['firewall_inspection_proven'])
                self.assert_all_closed(s)

    def test_seed_exact_fixed_create_only_put_and_201_empty_receipt(self):
        s = Scenario(self, role='seed', status=201, body=b'')
        result = self.run_case(s, 'seed', confirm_data=True)
        conn = next(c for c in s.connections if not c.imds)
        method, path, body, headers = conn.requests[0]
        self.assertEqual((method, path), ('PUT', '/lab-data/proof.txt'))
        self.assertEqual(body, b'azure-pe-lab-v1\nPrivate Endpoint inspection proof.\n')
        self.assertEqual(headers['If-None-Match'], '*')
        self.assertEqual(headers['x-ms-blob-type'], 'BlockBlob')
        self.assertEqual(headers['Content-Type'], 'text/plain; charset=utf-8')
        self.assertEqual(headers['Authorization'], 'Bearer ' + FAKE_TOKEN)
        self.assertIn('x-ms-date', headers)
        self.assertEqual(len(conn.requests), 1)
        self.assertTrue(result['synthetic_blob_created'])
        self.assertFalse(result['authorized_blob_read_proven'])
        self.assertEqual(result['observation'], 'CREATE_ACCEPTED')
        self.assertEqual(result['response_body_sha256'], hashlib.sha256(b'').hexdigest())
        self.assertEqual(s.raw_sockets[0].bound, ('10.10.1.11', 0))
        self.assert_all_closed(s)

    def test_seed_conflicts_never_overwrite_delete_or_retry(self):
        for status in (409, 412):
            with self.subTest(status=status):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self, role='seed', status=status, body=b'fake conflict')
                result = self.run_case(s, 'seed', confirm_data=True)
                conn = next(c for c in s.connections if not c.imds)
                self.assertEqual(len(conn.requests), 1)
                self.assertEqual(conn.requests[0][0], 'PUT')
                self.assertEqual(conn.requests[0][3]['If-None-Match'], '*')
                self.assertFalse(result['synthetic_blob_created'])
                self.assertIn('not overwritten', result['note'])
                self.assertFalse(result['automatic_retry'])
                self.assert_all_closed(s)

    def test_seed_success_requires_201_and_empty_body(self):
        for status, body in [(200, b''), (202, b''), (201, b'not empty')]:
            with self.subTest(status=status, body=body):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self, role='seed', status=status, body=body)
                result = self.run_case(s, 'seed', confirm_data=True)
                self.assertFalse(result['synthetic_blob_created'])
                self.assertFalse(result['authorized_blob_read_proven'])

    def test_noauth_403_or_even_matching_200_never_proves_authorized_read(self):
        for role in ('reader', 'seed'):
            for status in (403, 200):
                with self.subTest(role=role, status=status):
                    self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                    self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                    s = Scenario(self, role=role, status=status)
                    result = self.run_case(s, 'noauth', confirm_token=False)
                    self.assertFalse(result['token_requested'])
                    self.assertFalse(result['token_acquired'])
                    self.assertFalse(result['authorized_blob_read_proven'])
                    self.assertFalse(result['synthetic_blob_created'])
                    self.assertFalse(result['private_path_proven'])
                    self.assertFalse(result['firewall_inspection_proven'])
                    self.assertEqual(len(s.http_calls), 1)
                    self.assertNotIn('Authorization', s.connections[0].requests[0][3])
                    self.assertIn('not authorized Blob access', result['note'])
                    self.assert_all_closed(s)

    def test_redirects_throttles_and_service_errors_are_single_attempt_no_proxy(self):
        env = {'HTTP_PROXY': 'http://proxy.invalid:8080', 'HTTPS_PROXY': 'http://proxy.invalid:8080',
               'ALL_PROXY': 'http://proxy.invalid:8080', 'http_proxy': 'http://proxy.invalid:8080',
               'https_proxy': 'http://proxy.invalid:8080', 'NO_PROXY': ''}
        for status in (301, 302, 303, 307, 308, 429, 500, 503):
            with self.subTest(status=status), mock.patch.dict(os.environ, env):
                self.out = self.root / ('case-' + str(len(list(self.root.iterdir()))))
                self.patch(probe, 'time', types.SimpleNamespace(time=lambda: NOW, monotonic=lambda: 100))
                s = Scenario(self, status=status, body=b'fake service error')
                s.blob_response.headers['Location'] = 'https://unowned.invalid/steal'
                result = self.run_case(s)
                self.assertNotIn('error_type', result)
                self.assertEqual(result['http_status'], status)
                self.assertEqual(len(s.raw_sockets), 1)
                self.assertEqual(len(s.http_calls), 2)
                self.assertTrue(all(len(c.requests) == 1 for c in s.connections))
                self.assertEqual([e for e in s.events if e[0] == 'connect'], [('connect', (E, 443))])
                self.assertFalse(result['automatic_redirect'])
                self.assertFalse(result['automatic_retry'])
                self.assertNotIn('Location', result['service_headers'])
                self.assert_all_closed(s)


class ResponseTests(OfflineCase):
    def test_body_limit_plus_one_is_read_and_oversized_body_not_preserved(self):
        s = Scenario(self, body=(FAKE_TOKEN.encode() * 300))
        result = self.run_case(s)
        self.assertEqual(s.blob_response.read_sizes, [probe.BODY_LIMIT + 1])
        self.assertEqual(result['response_body_bytes_observed'], probe.BODY_LIMIT + 1)
        self.assertTrue(result['response_body_truncated'])
        self.assertEqual(result['error_type'], 'ValueError')
        self.assertNotIn('response_body_sha256', result)
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assert_all_closed(s)

    def test_exact_body_bound_accepted_but_not_content_match(self):
        s = Scenario(self, body=b'X' * probe.BODY_LIMIT)
        result = self.run_case(s)
        self.assertFalse(result['response_body_truncated'])
        self.assertEqual(result['response_body_bytes_observed'], probe.BODY_LIMIT)
        self.assertFalse(result['authorized_blob_read_proven'])
        self.assertEqual(result['response_body_sha256'], hashlib.sha256(b'X' * probe.BODY_LIMIT).hexdigest())

    def test_service_headers_allowlist_and_safe_patterns(self):
        safe = {'x-ms-request-id': 'abc123-DEF', 'x-ms-client-request-id': CASE,
                'x-ms-error-code': 'AuthorizationFailure', 'content-length': '123', 'etag': '"0xABC123"'}
        response = FakeResponse(headers=dict(safe, **{'Authorization': FAKE_TOKEN,
            'Set-Cookie': FAKE_TOKEN, 'Location': 'https://unowned.invalid/' + FAKE_TOKEN,
            'Server': FAKE_TOKEN}))
        self.assertEqual(probe.safe_headers(response), safe)
        self.assertEqual(set(response.requested_headers), set(safe))

    def test_malicious_and_oversized_headers_are_dropped(self):
        bad = {'x-ms-request-id': ['abc\r\nAuthorization: ' + FAKE_TOKEN, 'a' * 81, '/', None, 3],
               'x-ms-client-request-id': ['not-a-uuid!', 'b' * 81],
               'x-ms-error-code': [FAKE_TOKEN, '<script>', 'a' * 129, 'Bad Error'],
               'content-length': ['-1', '1\n', '1e9', '1' * 13],
               'etag': ['"bad value"', 'a' * 97, FAKE_TOKEN, 'x\r\nInjected: 1']}
        for name, values in bad.items():
            for value in values:
                with self.subTest(name=name, value=repr(value)[:45]):
                    self.assertEqual(probe.safe_headers(FakeResponse(headers={name: value})), {})

    def test_server_error_body_and_headers_cannot_inject_raw_logs(self):
        s = Scenario(self, status=403, body=('malicious ' + FAKE_TOKEN).encode())
        s.blob_response.headers = {'x-ms-error-code': 'error-' + FAKE_TOKEN,
                                   'etag': FAKE_TOKEN, 'Authorization': 'Bearer ' + FAKE_TOKEN}
        result = self.run_case(s)
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assertFalse(result['authorized_blob_read_proven'])
        self.assertEqual(result['service_headers'], {})
        self.assertTrue(result['response_sensitive_echo_detected'])
        self.assertEqual(result['error_phase'], 'https-response')
        self.assertNotIn('response_body_sha256', result)
        self.assert_all_closed(s)

    def test_read_exception_closes_every_owned_socket(self):
        s = Scenario(self); s.blob_response.body = OSError('malicious-body ' + FAKE_TOKEN)
        result = self.run_case(s)
        self.assertEqual(result['error_phase'], 'https-response')
        self.assertNotIn(FAKE_TOKEN, self.evidence())
        self.assert_all_closed(s)


class ReadyTests(OfflineCase):
    def setup_ready(self):
        s = Scenario(self)
        ca = self.root / 'fake-public-ca.pem'
        ca.write_bytes(b'FAKE PUBLIC CA FIXTURE; NOT A REAL CERTIFICATE\n')
        self.patch(probe, 'CA_BUNDLE', str(ca))
        calls = []
        def dig(command, **kwargs):
            calls.append((command, kwargs))
            self.assertEqual(command[0], 'dig')
            return types.SimpleNamespace(stdout=command[2] + '. 60 IN A ' + E + '\n')
        self.patch(probe.subprocess, 'run', dig)
        return s, ca, calls

    def test_ready_checks_both_firewall_dns_names_ca_hash_but_no_token_or_tls(self):
        s, ca, calls = self.setup_ready()
        seen = []
        @contextlib.contextmanager
        def deadline(seconds):
            seen.append(seconds); yield
        self.patch(probe, 'deadline', deadline)
        result = probe.ready(s.config)
        self.assertEqual(result['status'], 'LOCAL_DNS_CLIENT_READY')
        self.assertEqual(result['interface'], 'eth-test')
        self.assertEqual(result['os_ipv4_answers'], [E])
        self.assertEqual(result['ca_bundle_sha256'], hashlib.sha256(ca.read_bytes()).hexdigest())
        self.assertEqual(result['ca_bundle_path'], str(ca))
        self.assertEqual(seen, [20])
        self.assertIn('no token', result['scope'])
        queries = [s.config['blob_fqdn'], 'offlinelab123.privatelink.blob.core.windows.net']
        self.assertEqual([c[0][2] for c in calls], queries)
        for command, kwargs in calls:
            self.assertEqual(command, ['dig', '@10.0.1.4', command[2], 'A', '+noall', '+answer', '+time=2', '+tries=1'])
            self.assertEqual(kwargs, {'capture_output': True, 'text': True, 'timeout': 5, 'check': True})
        self.assertEqual(s.http_calls, [])
        self.assertEqual(s.raw_sockets, [])
        self.assertNotIn('wrap', [row[0] for row in s.events])
        self.assertFalse(self.out.exists())

    def test_ready_rejects_mixed_public_empty_or_oversize_firewall_dns(self):
        for text in ('', 'x. 60 IN A 203.0.113.8\n',
                     'x. 60 IN A ' + E + '\nx. 60 IN A 203.0.113.8\n', 'X' * 8193):
            with self.subTest(text_length=len(text)):
                s, ca, calls = self.setup_ready()
                self.patch(probe.subprocess, 'run', mock.Mock(return_value=types.SimpleNamespace(stdout=text)))
                with self.assertRaises(ValueError):
                    probe.ready(s.config)
                self.assertEqual(s.http_calls, [])
                self.assertEqual(s.raw_sockets, [])

    def test_ready_ca_missing_or_insecure_context_is_rejected(self):
        s, ca, calls = self.setup_ready(); ca.unlink()
        with self.assertRaisesRegex(ValueError, 'CA bundle is missing'):
            probe.ready(s.config)
        self.assertEqual(s.http_calls, [])
        s, ca, calls = self.setup_ready(); s.check_hostname = False
        with self.assertRaisesRegex(ValueError, 'Strict TLS context unavailable'):
            probe.ready(s.config)
        self.assertEqual(s.http_calls, [])
        self.assertEqual(s.raw_sockets, [])


class CliTests(OfflineCase):
    def setup_cli(self, args, c=None):
        path = self.root / 'config.json'
        path.write_text(json.dumps(config() if c is None else c))
        self.patch(probe.sys, 'argv', ['probe.py'] + args)
        self.patch(probe.os, 'umask', mock.Mock())
        self.enter_env = mock.patch.dict(os.environ, {'PE_LAB_CONFIG': str(path)})
        self.enter_env.start(); self.addCleanup(self.enter_env.stop)

    def test_cli_ready_rejects_output_and_token_data_flags(self):
        for flag in (['--out', str(self.out)], ['--confirm-token-use'], ['--confirm-data-operation']):
            with self.subTest(flag=flag):
                self.setup_cli(['ready'] + flag)
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as exc:
                    probe.main()
                self.assertEqual(exc.exception.code, 2)
                self.assertIn('details suppressed', stderr.getvalue())
                self.assertFalse(self.out.exists())

    def test_cli_preflight_error_does_not_print_malicious_config(self):
        self.setup_cli(['read'], dict(config(), extra=FAKE_TOKEN))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as exc:
            probe.main()
        self.assertEqual(exc.exception.code, 2)
        self.assertNotIn(FAKE_TOKEN, stderr.getvalue())

    def test_cli_failed_probe_prints_only_redacted_evidence_and_exit3(self):
        s = Scenario(self); s.request_error = ValueError(FAKE_TOKEN)
        self.setup_cli(['read', '--out', str(self.out), '--confirm-token-use'])
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout), self.assertRaises(SystemExit) as exc:
            probe.main()
        self.assertEqual(exc.exception.code, 3)
        self.assertNotIn(FAKE_TOKEN, stdout.getvalue())
        self.assertIn('NEEDS_REVIEW', stdout.getvalue())
        self.assert_all_closed(s)


if __name__ == '__main__':
    unittest.main()
