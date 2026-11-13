#!/usr/bin/env python3
"""Offline contract tests: no DNS, socket, TLS, HTTP or child process is real.

Synthetic public-looking addresses are test inputs only. Fake TLS certificates
and contexts exercise configuration and error handling, NOT actual certificate
trust, a TLS handshake, Azure routing, WAF enforcement or service health.
Run: python3 -I -m unittest discover -s tests -p 'test_probe.py' -v
"""
import contextlib
import copy
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
import unittest
from unittest import mock
import urllib.request
import uuid


ROOT = Path(__file__).resolve().parents[1]
CASE = '12345678-1234-4123-8123-123456789abc'
CONFIG = {
    'edge_fqdn': 'fixture.azurefd.net',
    'origin_fqdn': 'origin.owned-domain.net',
    'gateway_public_ip': '93.184.216.34',
    'backend_fqdn': 'fixture.azurewebsites.net',
    'frontdoor_id': 'abcdefab-1234-4567-89ab-abcdefabcdef',
    'operator_cidr': '8.8.4.4/32',
}
EXPECTED = {
    'fixture': 'azure-waf-origin-v1',
    'case_id': CASE,
    'message': 'Layered WAF inspection proof.',
}
BODY = (json.dumps(EXPECTED, separators=(',', ':')) + '\n').encode()
DNS_IP = '93.184.216.34'
CA_PEM = '-----BEGIN CERTIFICATE-----\nSYNTHETIC-NOT-A-VALID-CERTIFICATE\n-----END CERTIFICATE-----\n'


class OfflineViolation(BaseException):
    """Cannot be swallowed by the production Exception/KeyboardInterrupt catch."""


def forbidden(*args, **kwargs):
    raise OfflineViolation('Offline test attempted an unmocked external operation')


@contextlib.contextmanager
def deny_external_operations():
    """Fail closed even if the implementation adds a fallback transport."""
    with contextlib.ExitStack() as stack:
        for owner, names in [
            (socket, ['socket', 'socketpair', 'create_connection', 'getaddrinfo',
                      'gethostbyname', 'gethostbyname_ex', 'gethostbyaddr']),
            (ssl, ['create_default_context', 'SSLContext']),
            (http.client, ['HTTPConnection', 'HTTPSConnection']),
            (urllib.request, ['urlopen']),
            (subprocess, ['Popen', 'run', 'call', 'check_call', 'check_output']),
            (os, ['system', 'popen']),
        ]:
            for name in names:
                stack.enter_context(mock.patch.object(owner, name, side_effect=forbidden))
        yield


# Import itself is covered: the test must never start a transport on import.
with deny_external_operations():
    SPEC = importlib.util.spec_from_file_location('waf_probe_under_test', ROOT / 'guest/probe.py')
    PROBE = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(PROBE)


class FakeRaw:
    def __init__(self, out, failure=None):
        self.out = out
        self.failure = failure
        self.bound = None
        self.connected = False
        self.closed = 0
        self.connects = []
        self.timeouts = []

    def settimeout(self, value):
        self.timeouts.append(value)

    def bind(self, address):
        self.bound = address
        if self.failure == 'bind':
            raise OSError('SECRET_RAW_BIND_DIAGNOSTIC')

    def getsockname(self):
        return ('10.0.0.8' if self.connected else self.bound[0], 41001)

    def getpeername(self):
        return (DNS_IP, 443)

    def connect(self, address):
        # Validate evidence at the instant connect would occur, not afterward.
        attempt = json.loads((self.out / 'attempt.json').read_text())
        assert attempt['attempted_destination'] == list(address)
        assert attempt['attempted_local'] == [self.bound[0], 41001]
        assert attempt['case_id'] == CASE
        assert not (self.out / 'result.json').exists()
        self.connects.append(address)
        if self.failure == 'connect':
            raise TimeoutError('SECRET_CONNECT_DIAGNOSTIC')
        self.connected = True

    def close(self):
        self.closed += 1
        if self.failure == 'close':
            raise OSError('SECRET_CLOSE_DIAGNOSTIC')


class FakeTLS:
    # Deliberately not a certificate. This cannot verify public PKI trust.
    certificate = b'synthetic-not-an-x509-certificate'

    def __init__(self, failure=None):
        self.closed = 0
        self.failure = failure

    def version(self):
        return 'TLSv1.3'

    def getpeercert(self, binary_form=False):
        assert binary_form is True
        return self.certificate

    def close(self):
        self.closed += 1
        if self.failure == 'close':
            raise OSError('SECRET_TLS_CLOSE_DIAGNOSTIC')


class FakeTLSContext:
    def __init__(self, tls, failure=None):
        self.verify_mode = ssl.CERT_REQUIRED
        self.check_hostname = True
        self.minimum_version = None
        self.alpn = None
        self.tls = tls
        self.failure = failure
        self.wraps = []

    def set_alpn_protocols(self, protocols):
        self.alpn = protocols

    def wrap_socket(self, raw, server_hostname=None):
        self.wraps.append((raw, server_hostname))
        if self.failure == 'tls':
            raise ssl.SSLCertVerificationError('SECRET_CERT_DIAGNOSTIC')
        return self.tls


class FakeResponse:
    def __init__(self, body=BODY, status=200, headers=None, failure=None):
        self.body = body
        self.status = status
        self.headers = headers or {}
        self.failure = failure
        self.read_sizes = []
        self.requested_headers = []

    def read(self, size):
        self.read_sizes.append(size)
        if self.failure == 'read':
            raise TimeoutError('SECRET_BODY_DIAGNOSTIC')
        return self.body[:size]

    def getheader(self, name):
        self.requested_headers.append(name)
        return self.headers.get(name)


class FakeConnection:
    def __init__(self, response, failure=None):
        self.response = response
        self.failure = failure
        self.requests = []
        self.headers = []
        self.sent = 0
        self.responses = 0
        self.closed = 0
        self.sock = None
        self.auto_open = None

    def putrequest(self, *args, **kwargs):
        self.requests.append((args, kwargs))

    def putheader(self, *args):
        self.headers.append(args)

    def endheaders(self):
        self.sent += 1
        if self.failure == 'send':
            raise BrokenPipeError('SECRET_SEND_DIAGNOSTIC')

    def getresponse(self):
        self.responses += 1
        if self.failure == 'response':
            raise http.client.BadStatusLine('SECRET_RESPONSE_DIAGNOSTIC')
        return self.response

    def close(self):
        self.closed += 1
        if self.failure == 'close':
            raise OSError('SECRET_HTTP_CLOSE_DIAGNOSTIC')


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.guard = deny_external_operations()
        self.guard.__enter__()
        self.addCleanup(self.guard.__exit__, None, None, None)
        self.tmp = tempfile.TemporaryDirectory(prefix='offline-waf-tests-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.out = PROBE.new_out(self.root / 'evidence')
        self.ca_file = self.root / 'synthetic-public-ca.pem'
        self.ca_file.write_text(CA_PEM, encoding='ascii')
        self.config = copy.deepcopy(CONFIG)

    def execute(self, mode='edge-positive', failure=None, response=None,
                ips=None, confirm=False, local_address='0.0.0.0', strict=True,
                verify_mode=ssl.CERT_REQUIRED):
        self.raw = FakeRaw(self.out, failure)
        self.tls = FakeTLS(failure)
        self.ctx = FakeTLSContext(self.tls, failure)
        self.ctx.verify_mode = verify_mode
        if not strict:
            self.ctx.check_hostname = False
        self.response = response if response is not None else FakeResponse()
        self.conn = FakeConnection(self.response, failure)
        addresses = [DNS_IP] if ips is None else ips
        dns_rows = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', (ip, 443)) for ip in addresses]
        with contextlib.ExitStack() as stack:
            self.resolve_mock = stack.enter_context(mock.patch.object(
                PROBE.socket, 'getaddrinfo', return_value=dns_rows,
                side_effect=socket.gaierror('SECRET_DNS_DIAGNOSTIC') if failure == 'dns' else None))
            self.socket_mock = stack.enter_context(mock.patch.object(PROBE.socket, 'socket', return_value=self.raw))
            self.context_mock = stack.enter_context(mock.patch.object(PROBE.ssl, 'create_default_context', return_value=self.ctx))
            self.http_mock = stack.enter_context(mock.patch.object(PROBE.http.client, 'HTTPConnection', return_value=self.conn))
            self.deadline_mock = stack.enter_context(mock.patch.object(PROBE, 'deadline', return_value=contextlib.nullcontext()))
            self.uuid_mock = stack.enter_context(mock.patch.object(PROBE.uuid, 'uuid4', return_value=uuid.UUID(CASE)))
            stack.enter_context(mock.patch.object(PROBE.time, 'monotonic', side_effect=[100.0, 102.3456]))
            stack.enter_context(mock.patch.object(PROBE, 'utc', side_effect=['2026-11-04T00:00:00Z', '2026-11-04T00:00:02Z']))
            result = PROBE.run(self.config, mode, self.out, confirm, local_address, self.ca_file)
        self.assertEqual(json.loads((self.out / 'result.json').read_text()), result)
        self.assertEqual(json.loads((self.out / 'public-config.json').read_text()), self.config)
        self.assertEqual(result['duration_seconds'], 2.346)
        self.assertEqual(result['started_utc'], '2026-11-04T00:00:00Z')
        self.assertEqual(result['completed_utc'], '2026-11-04T00:00:02Z')
        for key in ['waf_block_proven', 'three_tls_legs_proven', 'origin_header_protection_proven']:
            self.assertIs(result[key], False)
        for artifact in self.out.iterdir():
            self.assertEqual(stat.S_IMODE(artifact.stat().st_mode), 0o600)
            self.assertNotIn('SECRET_', artifact.read_text())
        self.deadline_mock.assert_called_once_with(20)
        self.uuid_mock.assert_called_once_with()
        return result

    def test_offline_guard_cannot_be_swallowed_by_probe_exception_handler(self):
        for call in [lambda: socket.socket(), lambda: socket.getaddrinfo('never-resolve.test', 443),
                     lambda: ssl.create_default_context(), lambda: http.client.HTTPConnection('never-connect.test'),
                     lambda: subprocess.run(['never-execute']), lambda: os.system('never-execute')]:
            with self.subTest(call=call), self.assertRaises(OfflineViolation):
                call()
        with self.assertRaises(OfflineViolation):
            PROBE.run(CONFIG, 'edge-positive', self.out, ca_file=self.ca_file)
        self.assertFalse((self.out / 'attempt.json').exists())

    def test_exact_six_public_config_fields(self):
        self.assertIs(PROBE.validate_config(self.config), self.config)
        self.assertEqual(PROBE.KEYS, set(CONFIG))
        for field in CONFIG:
            candidate = copy.deepcopy(CONFIG)
            del candidate[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                PROBE.validate_config(candidate)
        for candidate in [None, [], 'config', {**CONFIG, 'password': 'not-allowed'}]:
            with self.subTest(candidate=type(candidate)), self.assertRaises(ValueError):
                PROBE.validate_config(candidate)

    def test_hostname_validation_rejects_private_invalid_and_injected_names(self):
        bad_names = ['', 'localhost', 'origin.localhost', 'origin.example', 'origin.invalid',
                     'https://origin.owned-domain.net', 'ORIGIN.owned-domain.net',
                     'origin.owned-domain.net.', 'origin.owned-domain.net:443',
                     'origin.owned-domain.net/path', '-a.owned-domain.net',
                     'a_.owned-domain.net', 'a' * 64 + '.net',
                     'x.' * 126 + 'net', 'a.net\r\nAuthorization: bad', 42, None]
        for value in bad_names:
            with self.subTest(value=value), self.assertRaises(ValueError):
                PROBE.validate_config({**CONFIG, 'origin_fqdn': value})
        for key, value in [('edge_fqdn', 'fixture.azurefd.net.attacker.net'),
                           ('backend_fqdn', 'fixture.azurewebsites.net.attacker.net')]:
            with self.subTest(field=key), self.assertRaises(ValueError):
                PROBE.validate_config({**CONFIG, key: value})

    def test_ipv4_scope_rejects_nonpublic_and_noncanonical_values(self):
        bad_ips = ['127.0.0.1', '10.0.0.1', '172.16.0.1', '192.168.0.1',
                   '169.254.169.254', '0.0.0.0', '100.64.0.1', '192.0.2.1',
                   '198.51.100.1', '203.0.113.1', '198.18.0.1', '224.0.0.1',
                   '240.0.0.1', '255.255.255.255', '::1', '2606:4700:4700::1111',
                   '093.184.216.34', '93.184.216.34/32', '93.184.216.34 ', 1234, None]
        for value in bad_ips:
            with self.subTest(value=value), self.assertRaises(ValueError):
                PROBE.public_ip(value)
        for value in ['8.8.4.4/24', '0.0.0.0/0', '127.0.0.1/32',
                      CONFIG['gateway_public_ip'] + '/32', None]:
            with self.subTest(operator=value), self.assertRaises(ValueError):
                PROBE.validate_config({**CONFIG, 'operator_cidr': value})

    def test_frontdoor_identifier_is_canonical_and_public_only(self):
        for value in [None, 5, '', CONFIG['frontdoor_id'].upper(),
                      '{' + CONFIG['frontdoor_id'] + '}',
                      CONFIG['frontdoor_id'] + '\n', 'not-a-guid']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                PROBE.validate_config({**CONFIG, 'frontdoor_id': value})

    def test_eleven_modes_and_duplicate_fdid_wire_intent(self):
        correct = CONFIG['frontdoor_id']
        wrong = '00000000-0000-0000-0000-000000000000'
        fdid = {
            'edge-positive': [], 'edge-block': [], 'regional-block': [],
            'direct-gateway': [('X-Azure-FDID', correct)], 'direct-backend': [],
            'fdid-missing': [], 'fdid-wrong': [('X-Azure-FDID', wrong)],
            'fdid-duplicate': [('X-Azure-FDID', correct), ('X-Azure-FDID', wrong)],
            'fdid-duplicate-valid': [('X-Azure-FDID', correct), ('X-Azure-FDID', correct)],
            'fdid-case': [('x-azure-fdid', correct.upper())],
            'fdid-correct': [('X-Azure-FDID', correct)],
        }
        self.assertEqual(len(PROBE.MODES), 11)
        self.assertEqual(set(PROBE.MODES), set(fdid))
        for mode in PROBE.MODES:
            headers = PROBE.request_headers(CONFIG, mode, CASE)
            with self.subTest(mode=mode):
                self.assertEqual([(k, v) for k, v in headers if k.lower() == 'x-azure-fdid'], fdid[mode])
                expected_host = CONFIG['edge_fqdn'] if mode in ['edge-positive', 'edge-block', 'regional-block'] else CONFIG['backend_fqdn'] if mode == 'direct-backend' else CONFIG['origin_fqdn']
                self.assertEqual(headers[0], ('Host', expected_host))
                self.assertIn(('User-Agent', 'azure-waf-lab/' + CASE), headers)
                self.assertIn(('X-Lab-Case-Id', CASE), headers)
                self.assertIn(('Connection', 'close'), headers)
                self.assertIn(('Cache-Control', 'no-cache'), headers)
                self.assertEqual(('X-Lab-Edge-Block', '1') in headers, mode == 'edge-block')
                self.assertEqual(('X-Lab-Regional-Block', '1') in headers, mode == 'regional-block')
                self.assertFalse({'cookie', 'authorization', 'proxy-authorization'} & {k.lower() for k, _ in headers})

    def test_diagnostic_modes_require_ack_before_evidence_or_transport(self):
        for mode in [x for x in PROBE.MODES if x.startswith('fdid-')]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                PROBE.run(CONFIG, mode, self.out)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_unknown_mode_and_invalid_bind_fail_before_transport(self):
        with self.assertRaises(ValueError):
            PROBE.run(CONFIG, 'not-a-mode', self.out)
        for address in [None, '::1', '10.0.0.1:4', '010.0.0.1', '0.0.0.0\n']:
            with self.subTest(address=address), self.assertRaises(ValueError):
                PROBE.run(CONFIG, 'edge-positive', self.out, local_address=address)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_success_has_preconnect_tuple_strict_tls_and_one_request(self):
        result = self.execute()
        self.assertEqual(result['observation'], 'FIXTURE_RESPONSE')
        for field in ['tcp_connect_completed', 'tls_completed', 'http_request_sent', 'fixture_content_match']:
            self.assertIs(result[field], True)
        self.assertEqual(result['attempted_local'], ['0.0.0.0', 41001])
        self.assertEqual(result['connected_local'], ['10.0.0.8', 41001])
        self.assertEqual(result['attempted_destination'], [DNS_IP, 443])
        self.assertEqual(result['connected_peer'], [DNS_IP, 443])
        self.assertEqual(result['dns_ipv4'], [DNS_IP])
        self.assertEqual(result['body_sha256'], hashlib.sha256(BODY).hexdigest())
        self.assertEqual(result['certificate_sha256'], hashlib.sha256(FakeTLS.certificate).hexdigest())
        self.assertEqual(result['body_bytes'], len(BODY))
        self.assertEqual(result['tls_version'], 'TLSv1.3')
        self.assertEqual(self.ctx.minimum_version, ssl.TLSVersion.TLSv1_2)
        self.assertEqual(self.ctx.alpn, ['http/1.1'])
        self.assertEqual(self.ctx.wraps, [(self.raw, CONFIG['edge_fqdn'])])
        self.resolve_mock.assert_called_once_with(CONFIG['edge_fqdn'], 443, family=socket.AF_INET, type=socket.SOCK_STREAM)
        self.socket_mock.assert_called_once_with(socket.AF_INET, socket.SOCK_STREAM)
        self.context_mock.assert_called_once_with(cadata=CA_PEM)
        self.assertEqual(result['ca_bundle_sha256'], hashlib.sha256(CA_PEM.encode()).hexdigest())
        self.assertIn('system/env stores not loaded', result['trust_source'])
        self.http_mock.assert_called_once_with(CONFIG['edge_fqdn'], 443, timeout=5)
        self.assertEqual(self.raw.timeouts, [5])
        self.assertEqual(self.raw.connects, [(DNS_IP, 443)])
        self.assertEqual(self.conn.auto_open, 0)
        self.assertIs(self.conn.sock, self.tls)
        self.assertEqual(self.conn.requests, [(('GET', '/probe/' + CASE), {'skip_host': True, 'skip_accept_encoding': True})])
        self.assertEqual(self.conn.headers, PROBE.request_headers(CONFIG, 'edge-positive', CASE))
        self.assertEqual((self.conn.sent, self.conn.responses), (1, 1))
        self.assertEqual(self.response.read_sizes, [8193])
        self.assertEqual((self.conn.closed, self.tls.closed, self.raw.closed), (1, 1, 1))
        self.assertIn('not the selected local interface', json.loads((self.out / 'attempt.json').read_text())['note'])

    def test_every_mode_preserves_headers_sni_and_destination(self):
        for index, mode in enumerate(PROBE.MODES):
            self.out = PROBE.new_out(self.root / ('mode-' + str(index)))
            with self.subTest(mode=mode):
                result = self.execute(mode, confirm=mode.startswith('fdid-'))
                headers = PROBE.request_headers(CONFIG, mode, CASE)
                self.assertEqual(self.conn.headers, headers)
                self.assertEqual(result['sni_host'], headers[0][1])
                self.assertEqual(self.ctx.wraps[0][1], headers[0][1])
                self.assertEqual(self.conn.sent, 1)

    def test_proxy_environment_and_redirect_do_not_create_another_request(self):
        response = FakeResponse(status=302, body=b'', headers={'Location': 'https://127.0.0.1/private'})
        with mock.patch.dict(os.environ, {'HTTPS_PROXY': 'http://127.0.0.1:9999', 'HTTP_PROXY': 'http://127.0.0.1:9999', 'ALL_PROXY': 'http://127.0.0.1:9999'}):
            result = self.execute(response=response)
        self.assertEqual(result['http_status'], 302)
        self.assertEqual(result['observation'], 'HTTP_RESPONSE_NEEDS_ATTRIBUTION')
        self.assertFalse(result['fixture_content_match'])
        self.assertEqual((len(self.raw.connects), self.conn.sent, self.conn.responses), (1, 1, 1))
        self.assertEqual(result['response_headers'], {})

    def test_dns_set_deduplicates_and_is_bounded_public_ipv4_only(self):
        for answers in [[], ['127.0.0.1'], ['::1'], [DNS_IP, '10.0.0.1'],
                        ['8.8.8.' + str(n) for n in range(1, 34)]]:
            self.out = PROBE.new_out(self.root / ('dns-' + str(len(list(self.root.iterdir())))))
            with self.subTest(answers=answers):
                result = self.execute(ips=answers)
                self.assertEqual(result['error_stage'], 'dns')
                self.assertEqual(result['error_class'], 'ValueError')
                self.socket_mock.assert_not_called()
                self.assertFalse((self.out / 'attempt.json').exists())
        self.out = PROBE.new_out(self.root / 'dns-dedup')
        result = self.execute(ips=[DNS_IP, '8.8.8.8', DNS_IP])
        self.assertEqual(result['dns_ipv4'], ['8.8.8.8', DNS_IP])
        self.assertEqual(result['attempted_destination'], ['8.8.8.8', 443])

    def test_direct_origin_requires_exact_owned_gateway_dns(self):
        for answers in [['8.8.8.8'], [DNS_IP, '8.8.8.8']]:
            self.out = PROBE.new_out(self.root / ('origin-dns-' + str(len(answers))))
            with self.subTest(answers=answers):
                result = self.execute(mode='direct-gateway', ips=answers)
                self.assertEqual(result['error_stage'], 'dns')
                self.socket_mock.assert_not_called()
                self.assertFalse((self.out / 'attempt.json').exists())

    def test_stage_failures_are_bounded_sanitized_and_close_created_handles(self):
        expected = {
            'dns': ('dns', 'gaierror', False, False, False, (0, 0, 0)),
            'bind': ('bind', 'OSError', False, False, False, (0, 0, 1)),
            'connect': ('connect', 'TimeoutError', False, False, False, (0, 0, 1)),
            'tls': ('tls', 'SSLCertVerificationError', True, False, False, (0, 0, 1)),
            'send': ('http', 'BrokenPipeError', True, True, False, (1, 1, 1)),
            'response': ('http', 'BadStatusLine', True, True, True, (1, 1, 1)),
            'read': ('http', 'TimeoutError', True, True, True, (1, 1, 1)),
        }
        for failure, (stage, error, tcp, tls, sent, closes) in expected.items():
            self.out = PROBE.new_out(self.root / ('failure-' + failure))
            with self.subTest(failure=failure):
                result = self.execute(failure=failure, response=FakeResponse(failure=failure))
                self.assertEqual(result['error_stage'], stage)
                self.assertEqual(result['error_class'], error)
                self.assertEqual(result['observation'], 'FAILED_BEFORE_COMPLETE_RESPONSE')
                self.assertEqual((result['tcp_connect_completed'], result['tls_completed'], result['http_request_sent']), (tcp, tls, sent))
                self.assertFalse(result['fixture_content_match'])
                self.assertEqual((self.conn.closed, self.tls.closed, self.raw.closed), closes)
                self.assertLessEqual(len(self.raw.connects), 1)
                self.assertLessEqual(self.conn.sent, 1)
                self.assertEqual((self.out / 'attempt.json').exists(), failure not in ['dns', 'bind'])

    def test_close_errors_do_not_hide_result_or_prevent_other_closes(self):
        result = self.execute(failure='close')
        self.assertEqual(result['observation'], 'FIXTURE_RESPONSE')
        self.assertEqual((self.conn.closed, self.tls.closed, self.raw.closed), (1, 1, 1))

    def test_non_strict_tls_context_fails_before_wrap_or_http(self):
        for index, kwargs in enumerate([{'strict': False}, {'verify_mode': ssl.CERT_NONE}, {'verify_mode': ssl.CERT_OPTIONAL}]):
            self.out = PROBE.new_out(self.root / ('bad-context-' + str(index)))
            with self.subTest(kwargs=kwargs):
                result = self.execute(**kwargs)
                self.assertEqual(result['error_stage'], 'tls')
                self.assertEqual(result['error_class'], 'ValueError')
                self.assertEqual(self.ctx.wraps, [])
                self.http_mock.assert_not_called()
                self.assertEqual(self.raw.closed, 1)

    def test_explicit_ca_bytes_and_hash_ignore_environment_ca_overrides(self):
        with mock.patch.dict(os.environ, {'SSL_CERT_FILE': '/DO_NOT_READ', 'SSL_CERT_DIR': '/DO_NOT_READ'}):
            result = self.execute()
        self.context_mock.assert_called_once_with(cadata=CA_PEM)
        self.assertEqual(result['ca_bundle_sha256'], hashlib.sha256(CA_PEM.encode()).hexdigest())
        # This accepts a sentinel only because TLS parsing is mocked; no PKI claim.
        self.assertEqual(PROBE.load_ca_bundle(self.ca_file), (CA_PEM, hashlib.sha256(CA_PEM.encode()).hexdigest()))

    def test_ca_file_failure_prevents_dns_and_socket_creation(self):
        for index, body in enumerate([b'', b'not a certificate',
                                      b'BEGIN CERTIFICATE\nPRIVATE KEY',
                                      b'BEGIN CERTIFICATE\n\xff',
                                      b'BEGIN CERTIFICATE' + b'x' * 4194304]):
            self.out = PROBE.new_out(self.root / ('ca-failure-' + str(index)))
            self.ca_file.write_bytes(body)
            with self.subTest(index=index):
                result = self.execute()
                self.assertEqual(result['error_stage'], 'trust-bundle')
                self.assertFalse(result['tcp_connect_completed'])
                self.assertNotIn('ca_bundle_sha256', result)
                self.resolve_mock.assert_not_called()
                self.socket_mock.assert_not_called()
                self.assertFalse((self.out / 'attempt.json').exists())
        self.out = PROBE.new_out(self.root / 'ca-missing')
        self.ca_file.unlink()
        result = self.execute()
        self.assertEqual(result['error_stage'], 'trust-bundle')
        self.assertEqual(result['error_class'], 'FileNotFoundError')
        self.resolve_mock.assert_not_called()

    def test_ca_read_has_fixed_limit_and_accepts_exact_maximum(self):
        prefix = b'BEGIN CERTIFICATE\n'
        content = prefix + b'x' * (4194304 - len(prefix))
        self.ca_file.write_bytes(content)
        pem, digest = PROBE.load_ca_bundle(self.ca_file)
        self.assertEqual(len(pem), 4194304)
        self.assertEqual(digest, hashlib.sha256(content).hexdigest())
        stream = mock.MagicMock()
        stream.__enter__.return_value.read.return_value = CA_PEM.encode()
        with mock.patch.object(PROBE.Path, 'open', return_value=stream):
            PROBE.load_ca_bundle('mocked-file')
        stream.__enter__.return_value.read.assert_called_once_with(4194305)

    def test_response_body_bound_is_8192_bytes_and_no_raw_body_is_saved(self):
        for size, failed in [(8191, False), (8192, False), (8193, True), (100000, True)]:
            self.out = PROBE.new_out(self.root / ('body-' + str(size)))
            with self.subTest(size=size):
                result = self.execute(response=FakeResponse(body=b'x' * size))
                self.assertEqual(self.response.read_sizes, [8193])
                self.assertEqual('error_class' in result, failed)
                self.assertNotIn('body', result)
                self.assertNotIn('response_body', result)
                if not failed:
                    self.assertEqual(result['body_bytes'], size)
                    self.assertEqual(result['body_sha256'], hashlib.sha256(b'x' * size).hexdigest())
                else:
                    self.assertEqual(result['error_stage'], 'http')
                    self.assertNotIn('body_sha256', result)

    def test_fixture_match_requires_exact_json_object_and_200(self):
        cases = [
            (403, BODY), (500, BODY), (200, b''), (200, b'<html>blocked</html>'),
            (200, b'\xff'), (200, b'null'), (200, b'[]'),
            (200, json.dumps({**EXPECTED, 'extra': True}).encode()),
            (200, json.dumps({**EXPECTED, 'case_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}).encode()),
            (200, json.dumps({**EXPECTED, 'fixture': 'other'}).encode()),
            (200, json.dumps({'fixture': EXPECTED['fixture'], 'case_id': CASE}).encode()),
        ]
        for index, (status, body) in enumerate(cases):
            self.out = PROBE.new_out(self.root / ('mismatch-' + str(index)))
            with self.subTest(index=index):
                result = self.execute(response=FakeResponse(status=status, body=body))
                self.assertFalse(result['fixture_content_match'])
                self.assertEqual(result['observation'], 'HTTP_RESPONSE_NEEDS_ATTRIBUTION')
                self.assertNotIn('error_class', result)

    def test_only_safe_bounded_response_headers_are_retained(self):
        headers = {'X-Azure-Ref': 'Ref_123+/=:-', 'X-Lab-Fixture': 'azure-waf-origin-v1',
                   'Content-Length': '12345678', 'Content-Type': 'application/json; charset=utf-8',
                   'Set-Cookie': 'SECRET_COOKIE', 'Authorization': 'SECRET_TOKEN',
                   'X-Forwarded-For': 'SECRET_IP', 'Server': 'SECRET_SERVER'}
        result = self.execute(response=FakeResponse(headers=headers))
        self.assertEqual(result['response_headers'], {k.lower(): headers[k] for k in ['X-Azure-Ref', 'X-Lab-Fixture', 'Content-Length', 'Content-Type']})
        self.assertEqual(set(self.response.requested_headers), {'X-Azure-Ref', 'X-Lab-Fixture', 'Content-Length', 'Content-Type'})

    def test_response_header_limits_and_duplicate_redaction(self):
        candidates = [
            {'X-Azure-Ref': 'a' * 256, 'X-Lab-Fixture': 'a' * 80, 'Content-Length': '1' * 8, 'Content-Type': 'a' * 100},
            {'X-Azure-Ref': 'a' * 257, 'X-Lab-Fixture': 'a' * 81, 'Content-Length': '1' * 9, 'Content-Type': 'a' * 101},
            {'X-Azure-Ref': 'one, two', 'X-Lab-Fixture': 'one, two', 'Content-Length': '12, 12', 'Content-Type': 'text/plain, text/plain'},
            {'X-Azure-Ref': 'a\r\nsecret', 'X-Lab-Fixture': 'a b', 'Content-Length': '-1', 'Content-Type': 'text/plain\nsecret'},
            {'X-Azure-Ref': None, 'X-Lab-Fixture': 123, 'Content-Length': '', 'Content-Type': []},
        ]
        for index, headers in enumerate(candidates):
            self.out = PROBE.new_out(self.root / ('header-' + str(index)))
            with self.subTest(index=index):
                result = self.execute(response=FakeResponse(headers=headers))
                self.assertEqual(result['response_headers'], {k.lower(): v for k, v in headers.items()} if index == 0 else {})

    def test_real_http_parser_duplicate_headers_over_fake_bytes_only(self):
        # HTTPResponse parses a BytesIO stream; it cannot resolve or connect.
        response_bytes = (b'HTTP/1.1 200 OK\r\n'
                          b'X-Azure-Ref: first\r\nX-Azure-Ref: second\r\n'
                          b'X-Lab-Fixture: azure-waf-origin-v1\r\n'
                          b'Content-Type: application/json\r\n'
                          b'Content-Length: ' + str(len(BODY)).encode() + b'\r\n\r\n' + BODY)
        fake_sock = mock.Mock()
        fake_sock.makefile.return_value = io.BytesIO(response_bytes)
        parsed = http.client.HTTPResponse(fake_sock)
        parsed.begin()
        result = self.execute(response=parsed)
        self.assertTrue(result['fixture_content_match'])
        self.assertNotIn('x-azure-ref', result['response_headers'])
        self.assertEqual(result['response_headers']['x-lab-fixture'], EXPECTED['fixture'])
        fake_sock.makefile.assert_called_once_with('rb')
        fake_sock.connect.assert_not_called()

    def test_output_directory_is_private_new_and_non_symlink(self):
        self.assertEqual(stat.S_IMODE(self.out.stat().st_mode), 0o700)
        for existing in [self.out, self.root]:
            with self.subTest(existing=existing), self.assertRaises(ValueError):
                PROBE.new_out(existing)
        link = self.root / 'link'
        link.symlink_to(self.out, target_is_directory=True)
        for path in [link, link / 'child']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                PROBE.new_out(path)
        dangling = self.root / 'dangling'
        dangling.symlink_to(self.root / 'absent')
        with self.assertRaises(ValueError):
            PROBE.new_out(dangling)

    def test_json_outputs_refuse_overwrite_and_symlink(self):
        path = self.out / 'record.json'
        PROBE.write_json(path, {'original': True})
        before = path.read_bytes()
        with self.assertRaises(FileExistsError):
            PROBE.write_json(path, {'replacement': True})
        self.assertEqual(path.read_bytes(), before)
        alias = self.out / 'alias.json'
        alias.symlink_to(path)
        with self.assertRaises(FileExistsError):
            PROBE.write_json(alias, {'replacement': True})
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_completed_evidence_cannot_be_reused_for_a_second_request(self):
        self.execute()
        before = {p.name: p.read_bytes() for p in self.out.iterdir()}
        with self.assertRaises(FileExistsError):
            # No transport overrides here: any unexpected second call is denied.
            PROBE.run(CONFIG, 'edge-positive', self.out)
        self.assertEqual({p.name: p.read_bytes() for p in self.out.iterdir()}, before)

    def test_deadline_arms_and_restores_without_real_timers(self):
        previous = object()
        with mock.patch.object(PROBE.signal, 'signal', return_value=previous) as handler, mock.patch.object(PROBE.signal, 'setitimer') as timer:
            with PROBE.deadline(20):
                installed = handler.call_args_list[0].args[1]
                with self.assertRaises(TimeoutError):
                    installed(signal.SIGALRM, None)
            self.assertEqual(timer.call_args_list, [mock.call(signal.ITIMER_REAL, 20), mock.call(signal.ITIMER_REAL, 0)])
            self.assertEqual(handler.call_args_list[-1], mock.call(signal.SIGALRM, previous))
        with mock.patch.object(PROBE.signal, 'signal', return_value=previous) as handler, mock.patch.object(PROBE.signal, 'setitimer') as timer:
            with self.assertRaises(RuntimeError):
                with PROBE.deadline(20):
                    raise RuntimeError('local test exception')
            self.assertEqual(timer.call_args_list[-1], mock.call(signal.ITIMER_REAL, 0))
            self.assertEqual(handler.call_args_list[-1], mock.call(signal.SIGALRM, previous))

    def test_cli_validation_does_not_echo_config_or_create_output(self):
        config_file = self.root / 'bad-config.json'
        config_file.write_text(json.dumps({**CONFIG, 'secret': 'SECRET_DO_NOT_ECHO'}))
        requested_out = self.root / 'cli-output'
        output = io.StringIO()
        with mock.patch('sys.argv', ['probe.py', '--config', str(config_file), '--mode', 'edge-positive', '--out', str(requested_out)]), contextlib.redirect_stdout(output):
            self.assertEqual(PROBE.main(), 2)
        self.assertNotIn('SECRET', output.getvalue())
        self.assertFalse(requested_out.exists())

    def test_cli_diagnostic_acknowledgement_is_checked_before_output_creation(self):
        config_file = self.root / 'public.json'
        config_file.write_text(json.dumps(CONFIG))
        requested_out = self.root / 'cli-unapproved'
        output = io.StringIO()
        with mock.patch('sys.argv', ['probe.py', '--config', str(config_file), '--mode', 'fdid-missing', '--out', str(requested_out)]), contextlib.redirect_stdout(output):
            self.assertEqual(PROBE.main(), 2)
        self.assertFalse(requested_out.exists())
        self.assertIn('no details printed', output.getvalue())

    def test_cli_forwards_reviewed_ca_bind_and_ack_and_reports_exit_status(self):
        config_file = self.root / 'public.json'
        config_file.write_text(json.dumps(CONFIG))
        for failed, expected_exit in [(False, 0), (True, 3)]:
            requested_out = self.root / ('cli-failed' if failed else 'cli-success')
            record = {'case_id': CASE, 'observation': 'FAILED_BEFORE_COMPLETE_RESPONSE' if failed else 'FIXTURE_RESPONSE'}
            if failed:
                record['error_class'] = 'TimeoutError'
            output = io.StringIO()
            args = ['probe.py', '--config', str(config_file), '--mode', 'fdid-correct',
                    '--out', str(requested_out), '--confirm-diagnostic-ingress',
                    '--local-address', '10.0.0.8', '--ca-file', str(self.ca_file)]
            with self.subTest(failed=failed), mock.patch('sys.argv', args), mock.patch.object(PROBE, 'run', return_value=record) as run, contextlib.redirect_stdout(output):
                self.assertEqual(PROBE.main(), expected_exit)
            run.assert_called_once_with(CONFIG, 'fdid-correct', requested_out, True, '10.0.0.8', str(self.ca_file))
            self.assertEqual(json.loads(output.getvalue()), {'out': str(requested_out), 'case_id': CASE, 'observation': record['observation'], 'waf_block_proven': False})
            self.assertEqual(stat.S_IMODE(requested_out.stat().st_mode), 0o700)


if __name__ == '__main__':
    unittest.main()
