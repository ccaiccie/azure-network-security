"""Guarded loopback tests only. No Azure, package install, or host mutation."""

import contextlib
import hashlib
import http.client
import importlib.util
import io
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixture = load("gwlb_fixture", ROOT / "fixtures/server.py")
probe = load("gwlb_probe", ROOT / "guest/probe.py")
CONFIG = {"client_public_ip": "8.8.4.4", "consumer_public_ip": "1.1.1.1", "backend_ip": "10.20.1.20"}
# The public values above are parser-only examples. Any attempted socket to them
# is forbidden by GuardedTest; all actual listeners/connections use loopback.


class GuardedTest(unittest.TestCase):
    def setUp(self):
        original_connect = socket.socket.connect
        original_bind = socket.socket.bind

        def guarded_connect(sock, address):
            if not isinstance(address, tuple) or address[0] != "127.0.0.1":
                raise AssertionError("Network test attempted non-loopback connect: " + repr(address))
            return original_connect(sock, address)

        def guarded_bind(sock, address):
            if not isinstance(address, tuple) or address[0] != "127.0.0.1":
                raise AssertionError("Network test attempted non-loopback bind: " + repr(address))
            return original_bind(sock, address)

        for target, value in (("socket.socket.connect", guarded_connect), ("socket.socket.bind", guarded_bind),
                              ("socket.getaddrinfo", unittest.mock.Mock(side_effect=AssertionError("DNS is forbidden in tests"))),
                              ("socket.getfqdn", unittest.mock.Mock(side_effect=AssertionError("Reverse DNS is forbidden in tests"))),
                              ("socket.gethostbyaddr", unittest.mock.Mock(side_effect=AssertionError("Reverse DNS is forbidden in tests"))),
                              ("socket.gethostbyname", unittest.mock.Mock(side_effect=AssertionError("DNS is forbidden in tests"))),
                              ("subprocess.run", unittest.mock.Mock(side_effect=AssertionError("Host commands must be explicitly mocked")))):
            patcher = patch(target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    @contextlib.contextmanager
    def server(self, factory=None, handler=None):
        if handler:
            server = fixture.BoundedServer(("127.0.0.1", 0), handler)
        else:
            server = (factory or fixture.make_server)("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server.server_address[1]
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def run_probe(self, port, mode="positive", size=262144, public_client="127.0.0.1", case="test-case"):
        out = probe.new_out(self.root / (case + "-" + str(time.time_ns())), case)
        with contextlib.redirect_stdout(io.StringIO()):
            result = probe.perform("127.0.0.1", port, case, mode, 5, size, out, "127.0.0.1",
                                   public_client=public_client, backend_ip="127.0.0.1")
        return out, result

    def request(self, port, path, case=None):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        conn.auto_open = 0
        conn.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock.settimeout(2)
        conn.sock.bind(("127.0.0.1", 0))
        conn.sock.connect(("127.0.0.1", port))
        try:
            conn.request("GET", path, headers={"X-Lab-Case-ID": case} if case is not None else {})
            response = conn.getresponse()
            return response.status, response.read(270000)
        finally:
            conn.close()


class ConfigTests(GuardedTest):
    def test_exact_public_config_and_nat_local_bind(self):
        self.assertEqual(probe.validate_config(CONFIG, "192.168.1.30", "positive"),
                         ("192.168.1.30", "1.1.1.1", 8080, "8.8.4.4"))
        self.assertEqual(probe.validate_config(CONFIG, "100.64.1.1", "alternate")[2], 8081)
        self.assertEqual(fixture.validate_config({"backend_ip": "10.20.1.20"}), "10.20.1.20")

    def test_reject_non_global_public_values(self):
        for value in ("192.0.2.1", "198.51.100.1", "203.0.113.1", "10.1.1.1", "127.0.0.1", "169.254.1.1", "0.0.0.0",
                      "100.64.1.1", "198.18.1.1", "224.0.0.1", "240.1.1.1", "192.0.0.9", "192.88.99.1", "localhost", "2001:4860:4860::8888", 1):
            for key in ("client_public_ip", "consumer_public_ip"):
                with self.subTest(value=value, key=key), self.assertRaises(ValueError):
                    probe.validate_config({**CONFIG, key: value}, "192.168.1.1", "positive")

    def test_strict_field_set_role_and_client_separation(self):
        for config in ({**CONFIG, "secret": "x"}, {**CONFIG, "client_public_ip": CONFIG["consumer_public_ip"]},
                       {**CONFIG, "backend_ip": "10.20.1.21"}, {}, []):
            with self.subTest(config=config), self.assertRaises(ValueError):
                probe.validate_config(config, "192.168.1.1", "positive")
        for source in ("127.0.0.1", "0.0.0.0", "localhost", "::1", "10.20.1.20", "1.1.1.1"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                probe.validate_config(CONFIG, source, "positive")
        with self.assertRaises(ValueError):
            fixture.validate_config({"backend_ip": "10.20.1.20", "client_public_ip": "8.8.4.4"})

    def test_nic_readonly_command_is_mocked_and_exact(self):
        rows = [{"ifname": "eth0", "addr_info": [{"local": "192.168.1.30"}]}]
        with patch.object(probe.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(rows))) as command:
            probe.validate_local_nic("192.168.1.30")
            command.assert_called_once_with(["ip", "-j", "-4", "addr", "show"], check=True, capture_output=True, text=True, timeout=5)
            with self.assertRaises(ValueError):
                probe.validate_local_nic("192.168.1.31")
        with patch.object(probe.subprocess, "run", return_value=SimpleNamespace(stdout='[{"ifname":"lo","addr_info":[{"local":"192.168.1.30"}]}]')):
            with self.assertRaises(ValueError):
                probe.validate_local_nic("192.168.1.30")

    def test_cli_missing_source_never_connects(self):
        with patch.object(sys, "argv", ["gwlb-probe", "positive", "--config", "unused"]), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as exc:
                probe.main()
            self.assertEqual(exc.exception.code, 2)

    def test_cli_rejects_config_before_ip_or_socket(self):
        path = self.root / "config.json"
        path.write_text(json.dumps({**CONFIG, "client_public_ip": "203.0.113.1"}))
        with patch.object(sys, "argv", ["gwlb-probe", "positive", "--config", str(path), "--source-ip", "192.168.1.1"]), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                probe.main()


class OutputTests(GuardedTest):
    def test_collision_symlink_and_parent_symlink_rejected(self):
        output = probe.new_out(self.root / "new", "case")
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
        with self.assertRaises(FileExistsError):
            probe.new_out(output, "case")
        link = self.root / "link"
        link.symlink_to(output, target_is_directory=True)
        with self.assertRaises(OSError):
            probe.new_out(link, "case")
        with self.assertRaises(OSError):
            probe.new_out(link / "nested", "case")
        with self.assertRaises(ValueError):
            probe.new_out(self.root / "new" / ".." / "other", "case")

    def test_evidence_files_private_and_immutable(self):
        path = self.root / "record.json"
        probe.write_json(path, {"ok": True})
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        with self.assertRaises(FileExistsError):
            probe.write_json(path, {"ok": False})
        self.assertEqual(json.loads(path.read_text()), {"ok": True})
        link = self.root / "link.json"
        link.symlink_to(path)
        with self.assertRaises(FileExistsError):
            probe.write_json(link, {})


class FixtureTests(GuardedTest):
    def test_fixture_success_identity_and_private_files(self):
        with self.server() as port:
            out, result = self.run_probe(port)
        self.assertEqual(result["fixture_identity"], "MATCH")
        self.assertTrue(result["fixture_response_complete"])
        self.assertEqual(result["observation"], "FIXTURE_RESPONSE")
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertFalse(result["gwlb_path_proven"])
        self.assertFalse(result["block_proven"])
        self.assertFalse(result["source_port_mapping_inferred"])
        self.assertIsNone(result["asserted_client_public_port"])
        self.assertTrue(result["body_size_verified"])
        self.assertTrue(result["body_sha256_verified"])
        self.assertEqual(result["observed_backend_server_tuple"], ["127.0.0.1", port])
        self.assertEqual(result["client_local"], result["attempted_local"])
        for path in out.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        for field in ("started_utc", "connect_attempt_utc", "connected_utc", "request_write_started_utc", "request_write_completed_utc", "response_headers_utc", "completed_utc"):
            self.assertEqual(datetime.fromisoformat(result[field]).utcoffset().total_seconds(), 0)
        self.assertLessEqual(result["started_utc"], result["connect_attempt_utc"])
        self.assertLessEqual(result["connect_attempt_utc"], result["completed_utc"])

    def test_backend_public_source_identity_mismatch(self):
        with self.server() as port:
            _out, result = self.run_probe(port, public_client="127.0.0.2")
        self.assertEqual(result["fixture_identity"], "MISMATCH")
        self.assertFalse(result["fixture_response_complete"])
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")

    def test_payload_exact_maximum_size_and_hash(self):
        with self.server() as port:
            out, result = self.run_probe(port, mode="payload")
        self.assertEqual(result["response_body_bytes_observed"], 262144)
        self.assertEqual(result["response_body_sha256_observed"], hashlib.sha256(fixture.payload_body(262144)).hexdigest())
        self.assertTrue(result["payload_pattern_verified"])
        self.assertTrue(result["fixture_response_complete"])
        self.assertEqual((out / "response-body-prefix.bin").stat().st_size, 8192)
        self.assertFalse(result["packet_fragmentation_proven"])
        self.assertFalse(result["gwlb_path_proven"])

    def test_payload_corruption_is_not_complete_even_with_self_reported_hash(self):
        with self.server() as port, patch.object(fixture, "payload_body", return_value=b"z" * 100):
            _out, result = self.run_probe(port, mode="payload", size=100)
        self.assertEqual(result["fixture_identity"], "MATCH")
        self.assertTrue(result["body_size_verified"])
        self.assertTrue(result["body_sha256_verified"])
        self.assertFalse(result["payload_pattern_verified"])
        self.assertFalse(result["fixture_response_complete"])
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")

    def test_payload_small_size(self):
        with self.server() as port:
            _out, result = self.run_probe(port, mode="payload", size=1)
        self.assertEqual(result["response_body_bytes_observed"], 1)
        self.assertTrue(result["payload_pattern_verified"])

    def test_payload_duration_and_case_bounds(self):
        for duration, size, case in ((4, 1, "ok"), (181, 1, "ok"), (5, 0, "ok"), (5, 262145, "ok"), (5, 1, "../x")):
            with self.subTest(duration=duration, size=size, case=case), self.assertRaises(ValueError):
                probe.perform("127.0.0.1", 1, case, "positive", duration, size, self.root, "127.0.0.1", public_client="127.0.0.1")

    def test_request_case_header_and_urls(self):
        with self.server() as port:
            for path, case, expected in (("/probe/id", None, 400), ("/probe/id", "wrong", 400),
                                          ("/stream/id?seconds=181", "id", 400), ("/stream/id?seconds=4", "id", 400),
                                          ("/payload/id?bytes=262145", "id", 400), ("/payload/id?bytes=0", "id", 400),
                                          ("/payload/id?bytes=1&bytes=2", "id", 400), ("/probe/id?x=1", "id", 404),
                                          ("/health/id", "id", 403), ("http://example.test/probe/id", "id", 404)):
                with self.subTest(path=path, case=case):
                    self.assertEqual(self.request(port, path, case)[0], expected)

    def test_finite_stream_completion(self):
        with self.server() as port:
            _out, result = self.run_probe(port, mode="stream")
        self.assertTrue(result["stream_complete"])
        self.assertTrue(result["fixture_response_complete"])
        self.assertEqual(result["frames_received"], 6)
        self.assertEqual(result["total_timeout_seconds"], 15)

    def test_local_readiness_requests_are_labeled(self):
        with self.server() as port, contextlib.redirect_stdout(io.StringIO()):
            row = fixture.ready_request("127.0.0.1", port, "local-ready-fixture")
        self.assertEqual(row["purpose"], "local-readiness")
        self.assertEqual(row["path"], "/health/local-ready-fixture")


class FailureTests(GuardedTest):
    def test_denied_connect_has_durable_pretuple_and_completion(self):
        # Hold a non-listening loopback port so a refusal is deterministic.
        reserve = socket.socket()
        reserve.bind(("127.0.0.1", 0))
        self.addCleanup(reserve.close)
        port = reserve.getsockname()[1]
        original = socket.socket.connect
        before = []

        def inspect(sock, address):
            files = list(self.root.glob("*/connection.json"))
            self.assertEqual(len(files), 1)
            before.append(json.loads(files[0].read_text()))
            return original(sock, address)

        with patch("socket.socket.connect", inspect):
            out, result = self.run_probe(port, mode="closed")
        self.assertEqual(len(before), 1)
        self.assertFalse(before[0]["tcp_connect_completed"])
        self.assertTrue(before[0]["http_request_not_sent"])
        self.assertEqual(before[0]["attempted_destination"], ["127.0.0.1", port])
        self.assertGreater(before[0]["attempted_local"][1], 0)
        self.assertTrue(probe.valid_time(result["completed_utc"]))
        self.assertFalse(result["tcp_connect_completed"])
        self.assertTrue(result["http_request_not_sent"])
        self.assertFalse((out / "request-started.json").exists())
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertFalse(result["block_proven"])

    def test_no_redirect_following_and_sensitive_headers_redacted(self):
        class Redirect(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", "http://do-not-contact.invalid/private?token=secret")
                self.send_header("Set-Cookie", "session=secret")
                self.send_header("X-Other", "secret")
                self.send_header("Content-Length", "5")
                self.end_headers()
                self.wfile.write(b"hello")
            def log_message(self, *args):
                pass
        with self.server(handler=Redirect) as port:
            _out, result = self.run_probe(port)
        rendered = json.dumps(result)
        self.assertNotIn("secret", json.dumps(result["response_headers"]))
        self.assertNotIn("do-not-contact", rendered)
        self.assertEqual(result["http_status"], 302)
        self.assertFalse(result["redirects_followed"])
        self.assertFalse(result["fixture_response_complete"])

    def test_partial_stream_not_complete(self):
        class Partial(fixture.Handler):
            def do_GET(self):
                case = self.headers["X-Lab-Case-ID"]
                peer = self.client_address
                local = self.connection.getsockname()
                row = {"fixture": fixture.FIXTURE_ID, "role": "backend", "case_id": case, "time_utc": fixture.utc(),
                       "frame": 0, "path": "/stream/" + case, "purpose": "external-client-probe",
                       "peer_ip": peer[0], "peer_port": peer[1], "server_ip": local[0], "server_port": local[1], "stream_end": False}
                body = (json.dumps(row) + "\n").encode()
                self.send_response(200)
                for field in probe.IDENTITY_FIELDS:
                    self.send_header("X-Lab-" + field.replace("_", "-"), str(row[field]))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)
                self.close_connection = True
        with self.server(handler=Partial) as port:
            _out, result = self.run_probe(port, mode="stream")
        self.assertEqual(result["fixture_identity"], "MATCH")
        self.assertFalse(result["stream_complete"])
        self.assertFalse(result["fixture_response_complete"])
        self.assertEqual(result["observation"], "PARTIAL_FIXTURE_RESPONSE")

    def test_socket_idle_timeout_and_total_deadline(self):
        class Stalled(BaseHTTPRequestHandler):
            def do_GET(self):
                time.sleep(0.5)
            def log_message(self, *args):
                pass
        with self.server(handler=Stalled) as port, patch.object(probe, "SOCKET_TIMEOUT_SECONDS", 0.08):
            _out, result = self.run_probe(port)
        self.assertEqual(result["observation"], "TRANSPORT_TIMEOUT")
        self.assertLess(result["elapsed_seconds"], 1)
        with self.server(handler=Stalled) as port, patch.object(probe, "FRESH_TOTAL_SECONDS", 0.08):
            _out, result = self.run_probe(port)
        self.assertEqual(result["error_type"], "TimeoutError")
        self.assertLess(result["elapsed_seconds"], 1)

    def test_aggregate_header_limit(self):
        class Excessive(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("X-Excessive", "x" * 9000)
                self.end_headers()
            def log_message(self, *args):
                pass
        with self.server(handler=Excessive) as port:
            _out, result = self.run_probe(port)
        self.assertEqual(result["error_type"], "LineTooLong")
        self.assertFalse(result["fixture_response_complete"])

    def test_large_untrusted_body_stops_at_frame_bound(self):
        class Excessive(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Length", "9000")
                self.end_headers()
                self.wfile.write(b"x" * 9000)
            def log_message(self, *args):
                pass
        with self.server(handler=Excessive) as port:
            out, result = self.run_probe(port)
        self.assertLessEqual((out / "response-body-prefix.bin").stat().st_size, 8192)
        self.assertEqual(result["error_type"], "ValueError")
        self.assertFalse(result["fixture_response_complete"])


class HealthTests(GuardedTest):
    def test_app_health_requires_both_fixture_responses(self):
        observations = [{"server_port": 8080}, {"server_port": 8081}]
        with patch.object(fixture, "check_listeners", return_value=observations) as check:
            with self.server(factory=fixture.make_health_server) as port:
                status, body = self.request(port, "/health")
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body)["ports"], [8080, 8081])
            check.assert_called_once_with("127.0.0.1")
        with patch.object(fixture, "check_listeners", side_effect=ConnectionRefusedError("fixture absent")):
            with self.server(factory=fixture.make_health_server) as port:
                status, body = self.request(port, "/health")
            self.assertEqual(status, 503)
            self.assertEqual(json.loads(body)["status"], "LOCAL_FIXTURES_NOT_READY")

    def test_ready_uses_exact_units_and_mocked_local_commands(self):
        units = ["azure-gwlb-fixture@8080.service", "azure-gwlb-fixture@8081.service", "azure-gwlb-app-health.service"]

        def command(argv):
            if argv[0] == "ip":
                return SimpleNamespace(stdout=json.dumps([{"ifname": "eth0", "addr_info": [{"local": "10.20.1.20"}]}]))
            if argv[:2] == ["systemctl", "list-units"]:
                return SimpleNamespace(stdout="\n".join(unit + " loaded active running" for unit in units))
            self.assertEqual(argv[:2], ["systemctl", "is-active"])
            self.assertIn(argv[2], units)
            return SimpleNamespace(stdout="active\n")

        with patch.object(fixture, "run_readonly", side_effect=command), patch.object(fixture, "check_listeners", return_value=[]) as check:
            result = fixture.check_local_ready({"backend_ip": "10.20.1.20"})
            self.assertEqual(result["status"], "LOCAL_APP_READY")
            check.assert_called_once_with("10.20.1.20")
            units.append("azure-gwlb-fixture@9090.service")
            with self.assertRaisesRegex(ValueError, "exact expected"):
                fixture.check_local_ready({"backend_ip": "10.20.1.20"})

    def test_check_listeners_contacts_only_two_fixed_ports(self):
        with patch.object(fixture, "ready_request", return_value={}) as request:
            fixture.check_listeners("10.20.1.20")
        self.assertEqual([(call.args[0], call.args[1]) for call in request.call_args_list], [("10.20.1.20", 8080), ("10.20.1.20", 8081)])
        self.assertTrue(all(call.args[2].startswith("local-ready-") for call in request.call_args_list))

    def test_unavailable_fixture_and_wrong_identity_fail_ready(self):
        reserve = socket.socket()
        reserve.bind(("127.0.0.1", 0))
        self.addCleanup(reserve.close)
        with self.assertRaises(OSError):
            fixture.ready_request("127.0.0.1", reserve.getsockname()[1], "local-ready-absent")
        with self.server() as port, patch.object(fixture, "FIXTURE_ID", "different-marker"), contextlib.redirect_stdout(io.StringIO()):
            # Server and client share fixture module, so change the returned row.
            with patch.object(fixture.json, "loads", return_value={}):
                with self.assertRaisesRegex(ValueError, "identity"):
                    fixture.ready_request("127.0.0.1", port, "local-ready-wrong")

    def test_services_unprivileged_and_only_documented_ports(self):
        for name in ("azure-gwlb-fixture@.service", "azure-gwlb-app-health.service"):
            text = (ROOT / "fixtures" / name).read_text()
            self.assertIn("DynamicUser=yes", text)
            self.assertIn("CapabilityBoundingSet=\n", text)
            self.assertNotIn("CAP_NET_BIND_SERVICE", text)
            self.assertIn("/etc/azure-gwlb-app.json", text)
        self.assertIn("--port %i", (ROOT / "fixtures/azure-gwlb-fixture@.service").read_text())
        self.assertIn("--health", (ROOT / "fixtures/azure-gwlb-app-health.service").read_text())


class WrapperTests(unittest.TestCase):
    """Run wrapper path logic with a fake interpreter, never the real probe."""

    def resolve_wrapper(self, checkout):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "package with spaces"
            scripts = root / "scripts"
            scripts.mkdir(parents=True)
            interpreter = root / "fake-python"
            interpreter.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
            interpreter.chmod(0o700)
            source = (ROOT / "scripts/gwlb-probe").read_text()
            self.assertEqual(source.count("/usr/bin/python3"), 1)
            wrapper = scripts / "gwlb-probe"
            # Mock only the interpreter executable, preserving all path-selection
            # logic and argument forwarding in the actual checked-in wrapper.
            wrapper.write_text(source.replace("/usr/bin/python3", '"' + str(interpreter) + '"'))
            if checkout:
                guest = root / "guest"
                guest.mkdir()
                (guest / "probe.py").write_text("raise AssertionError('The real probe must never execute')\n")
            arguments = ["positive", "--config", "public config.json", "--source-ip", "192.168.1.40",
                         "--out", "new output directory", "literal;not-a-command"]
            result = subprocess.run(["/bin/sh", str(wrapper), *arguments], check=True,
                                    capture_output=True, text=True, timeout=5,
                                    cwd=directory)
            expected_path = str(scripts / "../guest/probe.py") if checkout else "/opt/azure-gwlb-lab/probe.py"
            self.assertEqual(result.stdout.splitlines(), ["-I", expected_path, *arguments])
            self.assertEqual(result.stderr, "")

    def test_checkout_relative_probe_and_argument_forwarding(self):
        self.resolve_wrapper(checkout=True)

    def test_installed_probe_fallback_and_argument_forwarding(self):
        self.resolve_wrapper(checkout=False)


if __name__ == "__main__":
    unittest.main()
