#!/usr/bin/env python3
"""Offline fixture/helper tests. Guarded loopback sockets and command mocks only."""

import contextlib
import http.client
import importlib.util
import io
import ipaddress
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixture = load("forced_fixture", "fixtures/server.py")
probe = load("forced_probe", "guest/probe.py")
# Public-looking values below are mock data only. The process-wide socket guard forbids public I/O.
CONFIG = {"role": "app", "private_ip": "10.20.1.10", "app_ip": "10.20.1.10",
          "origin_ip": "10.50.1.20", "origin_public_ip": "20.42.0.10",
          "egress_public_ips": ["20.50.0.20"]}
ORIGIN_CONFIG = {**CONFIG, "role": "origin", "private_ip": "10.50.1.20"}
REAL_SOCKET = socket.socket
REAL_GETADDRINFO = socket.getaddrinfo
GUARDS = []


def require_loopback(address):
    try:
        allowed = isinstance(address, tuple) and ipaddress.ip_address(address[0]).is_loopback
    except ValueError:
        allowed = False
    if not allowed:
        raise AssertionError("Offline test attempted a non-loopback socket operation")


class LoopbackOnlySocket(REAL_SOCKET):
    def bind(self, address):
        require_loopback(address)
        return super().bind(address)

    def connect(self, address):
        require_loopback(address)
        return super().connect(address)

    def connect_ex(self, address):
        require_loopback(address)
        return super().connect_ex(address)


def local_lookup(host, port, *args, **kwargs):
    require_loopback((host, port))
    return REAL_GETADDRINFO(host, port, *args, **kwargs)


def setUpModule():
    GUARDS.extend([
        patch.object(socket, "socket", LoopbackOnlySocket),
        patch.object(socket, "getaddrinfo", side_effect=local_lookup),
        patch.object(subprocess, "run", side_effect=AssertionError("Offline test attempted a real subprocess")),
    ])
    for guard in GUARDS:
        guard.start()


def tearDownModule():
    for guard in reversed(GUARDS):
        guard.stop()


class FixtureProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = fixture.make_server("127.0.0.1", 0)
        cls.port = cls.server.server_address[1]
        cls.server.stream_enabled = True  # Test-only ephemeral loopback stream listener.
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.out = Path(self.temporary.name) / "case"
        self.out.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def request(self, path, extra=None, method="GET"):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            conn.request(method, path, headers={"X-Lab-Case-ID": "local-case", **(extra or {})})
            response = conn.getresponse()
            return response.status, response.read()
        finally:
            conn.close()

    def local_perform(self, stream=False, case="local-case"):
        return probe.perform("127.0.0.1", self.port, case, stream, 5,
                             self.out, source="127.0.0.1", origin_ip="127.0.0.1", egress_pool=("127.0.0.1",))

    def test_fixture_probe_records_actual_peer_port(self):
        status, body = self.request("/probe")
        row = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(row["fixture"], "azure-forced-origin-v1")
        self.assertEqual(row["case_id"], "local-case")
        self.assertEqual(row["peer_ip"], "127.0.0.1")
        self.assertGreater(row["peer_port"], 0)

    def test_fixture_health(self):
        status, body = self.request("/health")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["path"], "/health")

    def test_fixture_rejects_unknown_paths(self):
        for path in ("/", "/probe?query=x", "/../etc/passwd", "/health#x", "http://other/probe"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)

    def test_fixture_path_and_aggregate_header_bounds(self):
        self.assertEqual(self.request("/" + "x" * 300)[0], 414)
        self.assertEqual(self.request("/probe", {"X-Extra": "x" * 9000})[0], 431)
        self.assertEqual(self.request("/probe", {"X-One": "x" * 4500, "X-Two": "y" * 4500})[0], 431)

    def test_fixture_bad_case(self):
        self.assertEqual(self.request("/probe", {"X-Lab-Case-ID": "bad case"})[0], 400)

    def test_fixture_duplicate_case_rejected(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            conn.putrequest("GET", "/probe")
            conn.putheader("X-Lab-Case-ID", "one")
            conn.putheader("X-Lab-Case-ID", "two")
            conn.endheaders()
            response = conn.getresponse()
            self.assertEqual(response.status, 400)
            response.read()
        finally:
            conn.close()

    def test_fixture_request_body_rejected(self):
        self.assertEqual(self.request("/probe", {"Content-Length": "1"})[0], 400)
        self.assertEqual(self.request("/probe", {"Transfer-Encoding": "chunked"})[0], 400)

    def test_fixture_post_rejected(self):
        self.assertEqual(self.request("/probe", method="POST")[0], 405)

    def test_stream_rejected_on_non_stream_listener(self):
        with patch.object(self.server, "stream_enabled", False):
            self.assertEqual(self.request("/stream?seconds=5")[0], 400)

    def test_production_stream_only_origin_8080(self):
        self.assertFalse(fixture.BoundedServer.__dict__.get("stream_enabled", False))
        other = fixture.make_server("127.0.0.1", 0)
        try:
            self.assertFalse(other.stream_enabled)
        finally:
            other.server_close()
        source = (ROOT / "fixtures/server.py").read_text()
        self.assertIn("self.server_address == (ORIGIN_IP, 8080)", source)

    def test_stream_bounds_and_parameter_strictness(self):
        for path in ("/stream?seconds=0", "/stream?seconds=4", "/stream?seconds=181",
                     "/stream?seconds=x", "/stream?seconds=5&other=1", "/stream?seconds=5&other=",
                     "/stream?seconds=5&seconds=6", "/stream?seconds=5#x", "/stream?seconds=+5",
                     "/stream?seconds=5.0", "http://other/stream?seconds=5"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 400)

    def test_direct_probe_records_original_tuple_and_immutable_stages(self):
        result = self.local_perform()
        self.assertEqual(result["fixture_identity"], "MATCH", result)
        self.assertTrue(result["tcp_connect_completed"])
        self.assertTrue(result["fixture_response_complete"])
        self.assertTrue(result["source_tuple_preserved_observed"])
        self.assertFalse(result["http_request_not_sent"])
        self.assertGreater(result["attempted_local"][1], 0)
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertEqual(json.loads((self.out / "result.json").read_text()), result)
        before = json.loads((self.out / "connection.json").read_text())
        connected = json.loads((self.out / "connected.json").read_text())
        self.assertFalse(before["tcp_connect_completed"])
        self.assertTrue(before["http_request_not_sent"])
        self.assertNotIn("client_remote", before)
        self.assertTrue(connected["tcp_connect_completed"])
        self.assertEqual(connected["request_write_status"], "not-started")
        self.assertEqual(result["observed_fixture_peer_tuples"], [result["attempted_local"]])
        self.assertEqual(json.loads((self.out / "request-started.json").read_text())["request_write_status"], "attempting")
        self.assertEqual(json.loads((self.out / "request-written.json").read_text())["request_write_status"], "completed-not-proof-of-delivery")
        for name in ("connection.json", "connected.json", "request-started.json", "request-written.json", "result.json", "frames.ndjson"):
            self.assertEqual((self.out / name).stat().st_mode & 0o777, 0o600)

    def test_proxy_environment_cannot_redirect_probe_or_trigger_dns(self):
        with patch.dict(os.environ, {"HTTP_PROXY": "http://proxy.invalid:8888", "HTTPS_PROXY": "http://proxy.invalid:8888",
                                    "ALL_PROXY": "socks5://proxy.invalid:8888", "NO_PROXY": ""}), patch.object(
            socket, "getaddrinfo", side_effect=AssertionError("Probe must never resolve DNS")
        ):
            result = self.local_perform()
        self.assertEqual(result["fixture_identity"], "MATCH")
        self.assertEqual(result["client_remote"], ["127.0.0.1", self.port])

    def test_finite_stream_explicit_completion(self):
        result = self.local_perform(stream=True, case="local-stream")
        self.assertTrue(result["stream_complete"], result)
        self.assertGreaterEqual(result["frames_received"], 5)
        self.assertFalse(result["automatic_reconnect"])
        self.assertGreaterEqual(result["elapsed_seconds"], 4)
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")

    def test_readiness_identity_uses_explicit_local_source(self):
        row = fixture.ready_request("127.0.0.1", self.port, "local-readiness-case")
        self.assertEqual(row["peer_ip"], "127.0.0.1")
        self.assertGreater(row["peer_port"], 0)
        self.assertEqual(row["path"], "/health")

    def test_nonclobber_existing_out(self):
        (self.out / "keep").write_text("prior")
        with self.assertRaises(FileExistsError):
            probe.new_out(self.out, "other")
        self.assertEqual((self.out / "keep").read_text(), "prior")

    def test_nonclobber_symlink(self):
        link = Path(self.temporary.name) / "link"
        link.symlink_to(self.out, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            probe.new_out(link, "other")

    def test_write_once_preserves_prior_evidence(self):
        target = self.out / "record.json"
        probe.write_json(target, {"original": True})
        with self.assertRaises(FileExistsError):
            probe.write_json(target, {"original": False})
        self.assertEqual(json.loads(target.read_text()), {"original": True})

    def test_new_out_has_private_permissions(self):
        out = probe.new_out(Path(self.temporary.name) / "new", "case")
        self.assertEqual(out.stat().st_mode & 0o777, 0o700)

    def test_probe_rejects_dns_before_network(self):
        with patch.object(probe.socket, "socket") as create:
            with self.assertRaises(ValueError):
                probe.perform("example.com", 8080, "case", False, 5, self.out, source="127.0.0.1", origin_ip="127.0.0.1", egress_pool=("127.0.0.1",))
            with self.assertRaises(ValueError):
                probe.perform("127.0.0.1", 8080, "case", False, 5, self.out, source="example.com")
        create.assert_not_called()

    def test_invalid_parameters_before_network(self):
        with patch.object(probe.socket, "socket") as create:
            for duration in (0, 4, 181, True):
                with self.assertRaises(ValueError):
                    probe.perform("127.0.0.1", 8080, "case", True, duration, self.out, source="127.0.0.1", origin_ip="127.0.0.1", egress_pool=("127.0.0.1",))
            for case in ("bad case", "x" * 129, ""):
                with self.assertRaises(ValueError):
                    probe.perform("127.0.0.1", 8080, case, False, 5, self.out, source="127.0.0.1", origin_ip="127.0.0.1", egress_pool=("127.0.0.1",))
        create.assert_not_called()


class MockSocketTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.out = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_timeout_retains_preconnect_tuple_and_http_not_sent(self):
        outer = self

        class TimeoutSocket:
            def settimeout(self, value):
                pass

            def bind(self, value):
                self.bound = (value[0], 45678)

            def getsockname(self):
                return self.bound

            def connect(self, target):
                saved = json.loads((outer.out / "connection.json").read_text())
                outer.assertEqual(saved["attempted_local"], ["10.20.1.10", 45678])
                outer.assertFalse(saved["tcp_connect_completed"])
                outer.assertTrue(saved["http_request_not_sent"])
                outer.assertIn("connect_attempt_utc", saved)
                raise TimeoutError("MOCK SYN dropped")

            def close(self):
                pass

        with patch.object(probe.socket, "socket", return_value=TimeoutSocket()) as create, patch.object(
            probe.http.client.HTTPConnection, "request"
        ) as request:
            result = probe.perform("20.42.0.10", 8080, "closed-case", False, 5,
                                   self.out, source="10.20.1.10", mode="closed", egress_pool=CONFIG["egress_public_ips"])
        create.assert_called_once()
        request.assert_not_called()
        self.assertEqual(result["attempted_destination"], ["20.42.0.10", 8080])
        self.assertEqual(result["request_write_status"], "not-started")
        self.assertTrue(result["http_request_not_sent"])
        self.assertEqual(result["error_type"], "TimeoutError")
        self.assertEqual(result["fixture_identity"], "UNOBSERVED")
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertFalse((self.out / "connected.json").exists())

    def test_partial_write_is_not_reported_as_http_not_sent(self):
        sock = Mock()
        sock.getsockname.return_value = ("10.20.1.10", 45678)
        sock.getpeername.return_value = ("20.42.0.10", 8080)
        with patch.object(probe.socket, "socket", return_value=sock), patch.object(
            probe.http.client.HTTPConnection, "request", side_effect=BrokenPipeError("partial send unknown")
        ) as request:
            result = probe.perform("20.42.0.10", 8080, "partial", False, 5,
                                   self.out, source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        self.assertEqual(result["request_write_status"], "attempting")
        self.assertFalse(result["http_request_not_sent"])
        self.assertEqual(request.call_args.kwargs["headers"]["X-Lab-Case-ID"], "partial")
        self.assertEqual(request.call_args.kwargs["headers"]["User-Agent"], "azure-forced-lab/partial")
        self.assertTrue((self.out / "connected.json").exists())
        self.assertFalse((self.out / "request-written.json").exists())
        sock.connect.assert_called_once_with(("20.42.0.10", 8080))

    def test_actual_tuple_mismatch_stops_before_http(self):
        sock = Mock()
        sock.getsockname.return_value = ("10.20.1.10", 45678)
        sock.getpeername.return_value = ("10.30.1.99", 8080)
        with patch.object(probe.socket, "socket", return_value=sock), patch.object(
            probe.http.client.HTTPConnection, "request"
        ) as request:
            result = probe.perform("20.42.0.10", 8080, "tuple", False, 5,
                                   self.out, source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        request.assert_not_called()
        self.assertEqual(result["error_type"], "ValueError")
        self.assertTrue(result["http_request_not_sent"])

    def mock_response(self, row):
        response = Mock()
        response.status = 200
        response.getheaders.return_value = [("Content-Type", "application/json")]
        response.readline.side_effect = [(json.dumps(row) + "\n").encode(), b""]
        return response

    def test_public_destination_and_actual_translated_peer_are_separate(self):
        for q in (45678, 60000):
            with self.subTest(q=q):
                out = self.out / str(q)
                out.mkdir()
                sock = Mock()
                sock.getsockname.return_value = ("10.20.1.10", 45678)
                sock.getpeername.return_value = ("20.42.0.10", 8080)
                row = {"fixture": "azure-forced-origin-v1", "case_id": "translation",
                       "server_ip": "10.50.1.20", "server_port": 8080, "path": "/probe",
                       "peer_ip": "20.50.0.20", "peer_port": q, "frame": 0}
                with patch.object(probe.socket, "socket", return_value=sock), patch.object(
                    probe.http.client.HTTPConnection, "request"
                ), patch.object(probe.http.client.HTTPConnection, "getresponse", return_value=self.mock_response(row)), patch.object(
                    socket, "getaddrinfo"
                ) as resolve:
                    result = probe.perform("20.42.0.10", 8080, "translation", False, 5, out,
                                           source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
                self.assertEqual(result["fixture_identity"], "MATCH")
                self.assertFalse(result["expected_source_preserved"])
                self.assertFalse(result["source_tuple_preserved_observed"])
                self.assertTrue(result["egress_translation_observed"])
                self.assertEqual(result["observed_fixture_peer_tuples"], [["20.50.0.20", q]])
                self.assertEqual(result["observed_fixture_server_tuples"], [["10.50.1.20", 8080]])
                self.assertEqual(result["attempted_destination"], ["20.42.0.10", 8080])
                self.assertEqual(result["attempted_local"], ["10.20.1.10", 45678])
                self.assertEqual(result["outcome"], "NEEDS_REVIEW")
                self.assertRegex(result["completed_utc"], r"T.*\+00:00$")
                sock.bind.assert_called_once_with(("10.20.1.10", 0))
                sock.connect.assert_called_once_with(("20.42.0.10", 8080))
                resolve.assert_not_called()

    def test_bind_failure_has_completed_result_without_syn(self):
        sock = Mock()
        sock.bind.side_effect = OSError("source unavailable")
        with patch.object(probe.socket, "socket", return_value=sock):
            result = probe.perform("20.42.0.10", 8080, "bind-fail", False, 5, self.out,
                                   source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        self.assertTrue(result["http_request_not_sent"])
        self.assertFalse(result["tcp_connect_completed"])
        self.assertEqual(result["error_type"], "OSError")
        self.assertIn("completed_utc", result)
        self.assertTrue((self.out / "result.json").is_file())
        self.assertFalse((self.out / "connection.json").exists())
        sock.connect.assert_not_called()

    def test_wrong_bound_source_aborts_before_syn(self):
        sock = Mock()
        sock.getsockname.return_value = ("10.10.1.11", 45678)
        with patch.object(probe.socket, "socket", return_value=sock):
            result = probe.perform("20.42.0.10", 8080, "wrong-bind", False, 5, self.out,
                                   source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        self.assertEqual(result["error_type"], "ValueError")
        self.assertTrue(result["http_request_not_sent"])
        sock.connect.assert_not_called()

    def test_existing_connection_evidence_not_overwritten_or_connected(self):
        (self.out / "connection.json").write_text('{"original": true}')
        sock = Mock()
        sock.getsockname.return_value = ("10.20.1.10", 45678)
        with patch.object(probe.socket, "socket", return_value=sock):
            result = probe.perform("20.42.0.10", 8080, "collision", False, 5, self.out,
                                   source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        self.assertEqual(json.loads((self.out / "connection.json").read_text()), {"original": True})
        self.assertEqual(result["error_type"], "FileExistsError")
        sock.connect.assert_not_called()

    def test_unapproved_peer_preserved_as_mismatch(self):
        sock = Mock()
        sock.getsockname.return_value = ("10.20.1.10", 45678)
        sock.getpeername.return_value = ("20.42.0.10", 8080)
        row = {"fixture": "azure-forced-origin-v1", "case_id": "unapproved",
               "server_ip": "10.50.1.20", "server_port": 8080, "path": "/probe",
               "peer_ip": "20.50.0.99", "peer_port": 60000, "frame": 0}
        with patch.object(probe.socket, "socket", return_value=sock), patch.object(
            probe.http.client.HTTPConnection, "request"
        ), patch.object(probe.http.client.HTTPConnection, "getresponse", return_value=self.mock_response(row)):
            result = probe.perform("20.42.0.10", 8080, "unapproved", False, 5, self.out,
                                   source="10.20.1.10", egress_pool=CONFIG["egress_public_ips"])
        self.assertEqual(result["fixture_identity"], "MISMATCH")
        self.assertEqual(result["observed_fixture_peer_tuples"], [["20.50.0.99", 60000]])
        self.assertFalse(result["egress_translation_observed"])
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.row = {"fixture": "azure-forced-origin-v1", "case_id": "case",
                    "server_ip": "10.50.1.20", "server_port": 8080,
                    "peer_ip": "20.50.0.20", "peer_port": 60000, "path": "/probe"}

    def matches(self, row=None):
        return probe.identity(self.row if row is None else row, "case", "10.50.1.20", 8080,
                              "/probe", CONFIG["egress_public_ips"])

    def test_origin_private_and_approved_translated_peer(self):
        self.assertTrue(self.matches())
        for address in CONFIG["egress_public_ips"]:
            for port in (1, 45679, 60000, 65535):
                self.assertTrue(self.matches({**self.row, "peer_ip": address, "peer_port": port}))

    def test_private_original_source_or_unapproved_public_peer_rejected(self):
        for address in ("10.20.1.10", "10.0.0.4", "20.50.0.22", "20.42.0.10", "127.0.0.1"):
            self.assertFalse(self.matches({**self.row, "peer_ip": address}))

    def test_malformed_or_wrong_identity_rejected(self):
        for key, value in (("peer_port", True), ("peer_port", "60000"), ("peer_port", 0),
                           ("peer_port", -1), ("peer_port", 65536), ("peer_ip", []),
                           ("fixture", "azure-nva-origin-v1"), ("server_ip", "20.42.0.10"),
                           ("server_ip", "10.30.1.99"), ("server_port", "8080"),
                           ("case_id", "other"), ("path", "/health")):
            with self.subTest(key=key, value=value):
                self.assertFalse(self.matches({**self.row, key: value}))
        self.assertFalse(self.matches([]))


class ConfigAndReadinessTests(unittest.TestCase):
    def setUp(self):
        self.tool_guard = patch.object(fixture, "validate_local_tools")
        self.tool_guard.start()
        self.addCleanup(self.tool_guard.stop)
        self.config = ORIGIN_CONFIG
        self.addresses = [{"ifname": "eth0", "addr_info": [{"local": "10.50.1.20", "prefixlen": 24}]}]
        self.active = [8080, 8081, 8082]
        self.commands = []
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temporary.cleanup()

    def readonly(self, command, **kwargs):
        self.commands.append(command)
        if command[0] == "ip":
            output = json.dumps(self.addresses)
        elif "list-units" in command:
            output = "\n".join(f"azure-forced-fixture@{port}.service loaded active running Synthetic fixture" for port in self.active)
        else:
            output = "active\n"
        return subprocess.CompletedProcess(command, 0, output, "")

    def test_mode_contract(self):
        for mode in ("closed", "positive", "stream"):
            self.assertEqual(probe.validate_config(CONFIG, mode), ("10.20.1.10", "20.42.0.10", 8080))
        self.assertEqual(probe.validate_config(CONFIG, "alternate"), ("10.20.1.10", "20.42.0.10", 8081))
        self.assertEqual(probe.validate_config(CONFIG, "perimeter"), ("10.20.1.10", "20.42.0.10", 8082))
        for mode in probe.MODES:
            with self.assertRaises(ValueError):
                probe.validate_config(ORIGIN_CONFIG, mode)

    def test_app_readiness_no_listener_or_network(self):
        self.addresses[0]["addr_info"][0]["local"] = "10.20.1.10"
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request"
        ) as request, patch.object(fixture.socket, "socket") as create:
            result = fixture.check_local_ready(CONFIG)
        self.assertEqual(result["ports"], [])
        self.assertEqual(result["status"], "LOCAL_CLIENT_READY")
        request.assert_not_called()
        create.assert_not_called()
        self.assertEqual(self.commands, [["ip", "-j", "-4", "addr", "show"]])

    def test_initial_empty_pool_permits_local_readiness_not_public_probe(self):
        for config in (CONFIG, ORIGIN_CONFIG):
            config = {**config, "egress_public_ips": []}
            self.addresses[0]["addr_info"][0]["local"] = config["private_ip"]
            with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
                fixture, "ready_request", return_value={"local": True}
            ):
                result = fixture.check_local_ready(config)
            self.assertTrue(result["pool_not_ready"])
            self.assertFalse(result["egress_pool_ready"])
            with self.assertRaisesRegex(ValueError, "nonempty"):
                probe.validate_config(config, "positive")

    def test_origin_readiness_exact_three_ports(self):
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request", side_effect=lambda ip, port, case: {"port": port}
        ) as request:
            result = fixture.check_local_ready(ORIGIN_CONFIG)
        self.assertEqual(result["status"], "LOCAL_FIXTURES_READY")
        self.assertIn("no end-to-end", result["scope"])
        self.assertEqual([call.args[:2] for call in request.call_args_list], [("10.50.1.20", 8080), ("10.50.1.20", 8081), ("10.50.1.20", 8082)])
        self.assertEqual(self.commands[-3:], [
            ["systemctl", "is-active", "azure-forced-fixture@8080.service"],
            ["systemctl", "is-active", "azure-forced-fixture@8081.service"],
            ["systemctl", "is-active", "azure-forced-fixture@8082.service"],
        ])
        self.assertTrue(all(command[0] in ("ip", "systemctl") for command in self.commands))

    def test_fixed_address_on_loopback_is_not_nic_readiness(self):
        self.addresses[0]["ifname"] = "lo"
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(fixture, "ready_request") as request:
            with self.assertRaisesRegex(ValueError, "non-loopback"):
                fixture.check_local_ready(ORIGIN_CONFIG)
        request.assert_not_called()

    def test_missing_private_nic_rejected(self):
        self.addresses = []
        with patch.object(fixture, "run_readonly", side_effect=self.readonly):
            with self.assertRaisesRegex(ValueError, "non-loopback"):
                fixture.check_local_ready(ORIGIN_CONFIG)

    def test_missing_or_extra_active_units_rejected(self):
        for active in ([8080], [8080, 8081, 8082, 8083], []):
            self.active = active
            with self.subTest(active=active), patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(fixture, "ready_request") as request:
                with self.assertRaisesRegex(ValueError, "exact declared-role"):
                    fixture.check_local_ready(ORIGIN_CONFIG)
            request.assert_not_called()

    def test_inactive_unit_is_not_ready(self):
        def run(command):
            if "is-active" in command:
                raise subprocess.CalledProcessError(3, command)
            return self.readonly(command)
        with patch.object(fixture, "run_readonly", side_effect=run), patch.object(fixture, "ready_request") as request:
            with self.assertRaises(subprocess.CalledProcessError):
                fixture.check_local_ready(ORIGIN_CONFIG)
        request.assert_not_called()

    def test_failed_8081_listener_is_not_ready(self):
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request", side_effect=[{"port": 8080}, TimeoutError("mock fixture down")]
        ):
            with self.assertRaises(TimeoutError):
                fixture.check_local_ready(ORIGIN_CONFIG)

    def test_fixed_config_rejects_changes_before_commands(self):
        for key in ("private_ip", "app_ip", "origin_ip", "role"):
            with self.subTest(key=key), patch.object(fixture, "run_readonly") as run:
                with self.assertRaises(ValueError):
                    fixture.check_local_ready({**ORIGIN_CONFIG, key: "127.0.0.1"})
                with self.assertRaises(ValueError):
                    probe.validate_config({**CONFIG, key: "127.0.0.1"}, "positive")
            run.assert_not_called()

    def test_wrong_role_cli_stops_before_subprocess_or_network(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps(ORIGIN_CONFIG))
        with patch.dict(os.environ, {"FORCED_LAB_CONFIG": str(cfg)}), patch.object(
            sys, "argv", ["probe.py", "positive"]
        ), patch.object(probe.subprocess, "run") as run, patch.object(
            probe.socket, "socket"
        ) as create, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                probe.main()
        run.assert_not_called()
        create.assert_not_called()

    def test_reverse_on_app_rejected(self):
        with self.assertRaises(ValueError):
            probe.validate_config(CONFIG, "reverse")

    def test_cli_uses_approved_runtime_public_tuple_without_dns(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps(CONFIG))
        output = Path(self.temporary.name) / "new"
        self.addresses[0]["addr_info"][0]["local"] = "10.20.1.10"
        with patch.dict(os.environ, {"FORCED_LAB_CONFIG": str(cfg)}), patch.object(
            sys, "argv", ["probe.py", "alternate", "--out", str(output)]
        ), patch.object(probe.subprocess, "run", side_effect=self.readonly), patch.object(
            probe, "perform", return_value={"outcome": "NEEDS_REVIEW"}
        ) as perform, patch.object(socket, "getaddrinfo") as resolve, contextlib.redirect_stdout(io.StringIO()):
            probe.main()
        self.assertEqual(perform.call_args.args[:2], ("20.42.0.10", 8081))
        self.assertEqual(perform.call_args.args[-1], "10.20.1.10")
        self.assertEqual(perform.call_args.kwargs, {"mode": "alternate", "origin_ip": "10.50.1.20",
                                                  "egress_pool": ("20.50.0.20",)})
        self.assertRegex(perform.call_args.args[2], r"^forced-alternate-\d{8}T\d{6}Z-[a-f0-9]{12}$")
        self.assertEqual(json.loads((output / "runtime-config.json").read_text()), CONFIG)
        resolve.assert_not_called()

    def test_public_or_reserved_config_rejected_before_any_command(self):
        rejected = ("example.com", "10.0.0.1", "127.0.0.1", "0.0.0.0", "169.254.1.2", "100.64.0.1",
                    "192.0.2.10", "198.51.100.10", "203.0.113.10", "198.18.0.1", "192.0.0.8",
                    "192.88.99.1", "224.0.0.1", "240.0.0.1", "255.255.255.255", "::1", "2001:4860::1",
                    "20.042.0.10", "20.42.0.10/32", 123, None, [], True)
        for value in rejected:
            for field, replacement in (("origin_public_ip", value), ("egress_public_ips", [value])):
                config = {**CONFIG, field: replacement}
                with self.subTest(value=value, field=field), patch.object(fixture, "run_readonly") as run:
                    with self.assertRaises(ValueError):
                        probe.validate_config(config, "positive")
                    with self.assertRaises(ValueError):
                        fixture.check_local_ready(config)
                run.assert_not_called()
        for pool in ("20.50.0.20", None, ["20.50.0.20"] * 2, ["20.42.0.10"], ["20.50.0.20"] * 65):
            with self.subTest(pool=pool), self.assertRaises(ValueError):
                probe.validate_config({**CONFIG, "egress_public_ips": pool}, "positive")

    def test_egress_pool_limit_one_consistent_for_probe_and_readiness(self):
        pool = [f"20.50.0.{index}" for index in range(1, 18)]
        for module in (probe, fixture):
            accepted = {**CONFIG, "egress_public_ips": pool[:1]}
            self.assertEqual(len(module.validate_public_config(accepted)[3]), 1)
            with self.assertRaisesRegex(ValueError, "at most 1"):
                module.validate_public_config({**CONFIG, "egress_public_ips": pool})

    def test_empty_or_documentation_destination_cli_fails_without_network(self):
        for value in ("", "203.0.113.4", "10.50.1.20", "forced.example.com"):
            cfg = Path(self.temporary.name) / "config.json"
            cfg.write_text(json.dumps({**CONFIG, "origin_public_ip": value}))
            with patch.dict(os.environ, {"FORCED_LAB_CONFIG": str(cfg)}), patch.object(
                sys, "argv", ["probe.py", "positive"]
            ), patch.object(probe.subprocess, "run") as run, patch.object(
                probe.socket, "socket"
            ) as create, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    probe.main()
            run.assert_not_called()
            create.assert_not_called()

    def test_fixture_wrong_port_role_before_commands(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps(CONFIG))
        with patch.object(sys, "argv", ["server.py", "--config", str(cfg), "--port", "8080"]), patch.object(
            fixture, "run_readonly"
        ) as run, patch.object(fixture, "make_server") as make, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                fixture.main()
        run.assert_not_called()
        make.assert_not_called()

    def test_initial_empty_pool_origin_can_start_but_app_never_listens(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps({**ORIGIN_CONFIG, "egress_public_ips": []}))
        server = Mock()
        with patch.object(sys, "argv", ["server.py", "--config", str(cfg), "--port", "8080"]), patch.object(
            fixture, "run_readonly", side_effect=self.readonly
        ), patch.object(fixture, "make_server", return_value=server) as make, contextlib.redirect_stdout(io.StringIO()):
            fixture.main()
        make.assert_called_once_with("10.50.1.20", 8080)
        server.serve_forever.assert_called_once()

    def test_probe_cli_missing_or_loopback_source_nic_never_connects(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps(CONFIG))
        for addresses in ([], [{"ifname": "lo", "addr_info": [{"local": "10.20.1.10"}]}],
                          [{"ifname": "eth0", "addr_info": None}], [{"ifname": "eth0", "addr_info": []}]):
            self.addresses = addresses
            with patch.dict(os.environ, {"FORCED_LAB_CONFIG": str(cfg)}), patch.object(
                sys, "argv", ["probe.py", "positive"]
            ), patch.object(probe.subprocess, "run", side_effect=self.readonly), patch.object(
                probe.socket, "socket"
            ) as create, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    probe.main()
            create.assert_not_called()

    def test_config_unknown_fields_or_missing_fields_rejected(self):
        for config in ({**CONFIG, "extra": "not permitted"}, {k: v for k, v in CONFIG.items() if k != "role"}):
            with self.assertRaises(ValueError):
                probe.validate_config(config, "positive")
            with self.assertRaises(ValueError):
                fixture.validate_config(config)


class ToolReadinessTests(unittest.TestCase):
    def test_installed_tools_validated_without_running_them(self):
        with patch.object(fixture.shutil, "which", side_effect=lambda name: "/usr/bin/" + name), patch.object(
            fixture.Path, "is_file", return_value=True
        ), patch.object(fixture.os, "access", return_value=True), patch.object(fixture, "run_readonly") as run:
            fixture.validate_local_tools("app")
            fixture.validate_local_tools("origin")
        run.assert_not_called()

    def test_missing_tools_or_wrappers_rejected(self):
        with patch.object(fixture.shutil, "which", return_value=None):
            with self.assertRaises(ValueError):
                fixture.validate_local_tools("app")
        with patch.object(fixture.shutil, "which", return_value="/usr/bin/tool"), patch.object(
            fixture.Path, "is_file", return_value=False
        ):
            with self.assertRaises(ValueError):
                fixture.validate_local_tools("origin")


class BoundedFailureTests(unittest.TestCase):
    """All actual sockets are loopback; no systemd, guest routing or Azure calls."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.out = Path(self.temporary.name)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(3)
        self.port = self.listener.getsockname()[1]
        self.accepts = []
        self.requests = []
        self.stop = threading.Event()
        self.thread = None

    def tearDown(self):
        self.stop.set()
        self.listener.close()
        if self.thread is not None:
            self.thread.join(timeout=4)
            self.assertFalse(self.thread.is_alive())
        self.temporary.cleanup()

    def serve(self, write):
        def target():
            try:
                conn, peer = self.listener.accept()
                self.accepts.append(peer)
                with conn:
                    conn.settimeout(2)
                    self.requests.append(conn.recv(4096))
                    write(conn)
            except OSError:
                pass
        self.thread = threading.Thread(target=target, daemon=True)
        self.thread.start()

    def perform(self, stream=False):
        return probe.perform("127.0.0.1", self.port, "bounded-case", stream,
                             5, self.out, source="127.0.0.1", origin_ip="127.0.0.1", egress_pool=("127.0.0.1",))

    def test_slow_headers_total_deadline_without_reconnect(self):
        def slow(conn):
            conn.sendall(b"HTTP/1.1 200 OK\r\nX-Slow: ")
            while not self.stop.wait(0.02):
                conn.sendall(b"x")
        self.serve(slow)
        with patch.object(probe, "FRESH_TOTAL_SECONDS", 0.2):
            result = self.perform()
        self.assertEqual(result["error_type"], "TimeoutError", result)
        self.assertLess(result["elapsed_seconds"], 2)
        self.assertFalse(result["http_request_not_sent"])
        self.assertEqual(len(self.accepts), 1)
        self.assertIn(b"X-Lab-Case-ID: bounded-case\r\n", self.requests[0])
        self.assertIn(b"User-Agent: azure-forced-lab/bounded-case\r\n", self.requests[0])

    def test_total_deadline_outside_main_thread(self):
        def slow(conn):
            conn.sendall(b"HTTP/1.1 200 OK\r\nX-Slow: ")
            while not self.stop.wait(0.02):
                conn.sendall(b"x")
        self.serve(slow)
        results = []
        with patch.object(probe, "FRESH_TOTAL_SECONDS", 0.2):
            thread = threading.Thread(target=lambda: results.append(self.perform()))
            thread.start()
            thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(results[0]["error_type"], "TimeoutError")
        self.assertEqual(len(self.accepts), 1)

    def test_early_stream_eof_is_not_complete(self):
        def early(conn):
            row = {"fixture": "azure-forced-origin-v1", "case_id": "bounded-case",
                   "server_ip": "127.0.0.1", "server_port": self.port,
                   "peer_ip": "127.0.0.1", "peer_port": self.accepts[0][1],
                   "path": "/stream", "frame": 0}
            conn.sendall(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + (json.dumps(row) + "\n").encode())
        self.serve(early)
        result = self.perform(stream=True)
        self.assertEqual(result["fixture_identity"], "MATCH", result)
        self.assertFalse(result["stream_complete"])
        self.assertEqual(result["frames_received"], 1)
        self.assertEqual(len(self.accepts), 1)

    def test_malformed_response_saved_without_success(self):
        self.serve(lambda conn: conn.sendall(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n[]\n"))
        result = self.perform()
        self.assertEqual(result["error_type"], "ValueError")
        self.assertEqual(result["fixture_identity"], "UNOBSERVED")
        self.assertFalse(result["fixture_response_complete"])
        self.assertTrue((self.out / "result.json").is_file())

    def test_http_redirect_is_not_followed(self):
        self.serve(lambda conn: conn.sendall(b"HTTP/1.1 302 Found\r\nLocation: http://example.com/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
        result = self.perform()
        self.assertEqual(result["http_status"], 302)
        self.assertEqual(result["fixture_identity"], "UNOBSERVED")
        self.assertEqual(len(self.accepts), 1)
        self.assertFalse(result["automatic_retry"])

    def test_out_of_range_translated_port_is_identity_mismatch(self):
        def wrong(conn):
            row = {"fixture": "azure-forced-origin-v1", "case_id": "bounded-case",
                   "server_ip": "127.0.0.1", "server_port": self.port,
                   "peer_ip": "127.0.0.1", "peer_port": 65536, "path": "/probe", "frame": 0}
            conn.sendall(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + (json.dumps(row) + "\n").encode())
        self.serve(wrong)
        result = self.perform()
        self.assertEqual(result["fixture_identity"], "MISMATCH")
        self.assertFalse(result["source_tuple_preserved_observed"])
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")

    def test_test_network_guard_denies_external_address(self):
        with self.assertRaises(AssertionError):
            self.listener.connect(("192.0.2.1", 8080))
        with self.assertRaises(AssertionError):
            socket.getaddrinfo("example.com", 80)


if __name__ == "__main__":
    unittest.main(verbosity=2)
