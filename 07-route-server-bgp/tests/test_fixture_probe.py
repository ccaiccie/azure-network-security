#!/usr/bin/env python3
"""Offline tests: loopback HTTP and mocks only, never actual guest/cloud commands."""

import contextlib
import http.client
import importlib.util
import io
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
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixture = load("routeserver_fixture", "fixtures/server.py")
probe = load("routeserver_probe", "guest/probe.py")
CONFIG = {"role": "app", "private_ip": "10.10.1.10", "app_ip": "10.10.1.10",
          "destination_ip": "172.20.50.10", "remote_ip": "10.30.1.20"}
REMOTE_CONFIG = {**CONFIG, "role": "remote", "private_ip": "10.30.1.20"}


class FixtureProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = fixture.make_server("127.0.0.1", 0)
        cls.port = cls.server.server_address[1]
        cls.server.test_port = cls.port
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
        with patch.object(probe, "DESTINATION_IP", "127.0.0.1"), patch.dict(
            probe.OVERLAY_PEERS, {"nva1": "127.0.0.1", "nva2": "127.0.0.2"}, clear=True
        ):
            return probe.perform("127.0.0.1", self.port, case, stream, 5,
                                 self.out, source="127.0.0.1", expected_node="nva1")

    def test_fixture_probe_records_actual_peer_port(self):
        status, body = self.request("/probe")
        row = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(row["fixture"], "azure-routeserver-origin-v1")
        self.assertEqual(row["case_id"], "local-case")
        self.assertEqual(row["peer_ip"], "127.0.0.1")
        self.assertGreater(row["peer_port"], 0)

    def test_fixture_health(self):
        self.assertEqual(self.request("/health")[0], 200)

    def test_fixture_rejects_unknown_paths(self):
        for path in ("/", "/probe?query=x", "/../etc/passwd", "/health#x"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)

    def test_fixture_bounds(self):
        self.assertEqual(self.request("/" + "x" * 300)[0], 414)
        self.assertEqual(self.request("/probe", {"X-Extra": "x" * 9000})[0], 431)

    def test_fixture_bad_case(self):
        self.assertEqual(self.request("/probe", {"X-Lab-Case-ID": "bad case"})[0], 400)

    def test_fixture_post_rejected(self):
        self.assertEqual(self.request("/probe", method="POST")[0], 405)

    def test_stream_rejected_on_non_stream_listener(self):
        with patch.object(self.server, "test_port", -1):
            self.assertEqual(self.request("/stream?seconds=5")[0], 400)

    def test_stream_bounds(self):
        for path in ("/stream?seconds=0", "/stream?seconds=181", "/stream?seconds=x",
                     "/stream?seconds=5&other=1", "/stream?seconds=5&other=",
                     "/stream?seconds=5&seconds=6", "/stream?seconds=5#x"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 400)

    def test_direct_probe_records_identity_and_original_tuple(self):
        result = self.local_perform()
        self.assertEqual(result["fixture_identity"], "MATCH", result)
        self.assertTrue(result["tcp_connect_completed"])
        self.assertTrue(result["fixture_response_complete"])
        self.assertFalse(result["http_request_not_sent"])
        self.assertEqual(result["observed_nodes"], ["nva1"])
        self.assertGreater(result["attempted_local"][1], 0)
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertEqual(json.loads((self.out / "result.json").read_text()), result)

    def test_finite_stream_explicit_completion(self):
        result = self.local_perform(stream=True, case="local-stream")
        self.assertTrue(result["stream_complete"], result)
        self.assertGreaterEqual(result["frames_received"], 5)
        self.assertFalse(result["automatic_reconnect"])
        self.assertGreaterEqual(result["elapsed_seconds"], 4)

    def test_readiness_request_identity_uses_explicit_local_source(self):
        with patch.object(fixture, "DESTINATION_IP", "127.0.0.1"):
            row = fixture.ready_request(self.port, "local-readiness-case")
        self.assertEqual(row["peer_ip"], "127.0.0.1")
        self.assertEqual(row["case_id"], "local-readiness-case")

    def test_timeout_retains_preconnect_tuple_and_http_not_sent(self):
        outer = self

        class TimeoutSocket:
            def settimeout(self, value):
                self.timeout = value

            def bind(self, value):
                self.bound = (value[0], 45678)

            def getsockname(self):
                return self.bound

            def connect(self, target):
                saved = json.loads((outer.out / "connection.json").read_text())
                outer.assertEqual(saved["attempted_local"], ["10.10.1.10", 45678])
                outer.assertFalse(saved["tcp_connect_completed"])
                outer.assertTrue(saved["http_request_not_sent"])
                raise TimeoutError("MOCK SYN dropped")

            def close(self):
                pass

        with patch.object(probe.socket, "socket", return_value=TimeoutSocket()) as create:
            result = probe.perform("172.20.50.10", 8081, "negative-case", False, 5,
                                   self.out, source="10.10.1.10")
        create.assert_called_once()
        self.assertEqual(result["attempted_destination"], ["172.20.50.10", 8081])
        self.assertEqual(result["request_write_status"], "not-started")
        self.assertTrue(result["http_request_not_sent"])
        self.assertEqual(result["error_type"], "TimeoutError")
        self.assertEqual(result["fixture_identity"], "UNOBSERVED")
        self.assertEqual(result["outcome"], "NEEDS_REVIEW")
        self.assertFalse(result["tcp_connect_completed"])

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

    def test_new_out_has_private_permissions(self):
        out = probe.new_out(Path(self.temporary.name) / "new", "case")
        self.assertEqual(out.stat().st_mode & 0o777, 0o700)

    def test_probe_rejects_dns_before_network(self):
        with patch.object(probe.socket, "socket") as create:
            with self.assertRaises(ValueError):
                probe.perform("example.com", 8080, "case", False, 5, self.out)
        create.assert_not_called()

    def test_invalid_duration_before_network(self):
        with patch.object(probe.socket, "socket") as create:
            for duration in (0, 4, 181):
                with self.assertRaises(ValueError):
                    probe.perform("172.20.50.10", 8080, "case", True, duration, self.out)
        create.assert_not_called()

    def test_invalid_expected_node_before_network(self):
        with patch.object(probe.socket, "socket") as create:
            with self.assertRaises(ValueError):
                probe.perform("172.20.50.10", 8080, "case", False, 5, self.out, expected_node="other")
        create.assert_not_called()

    def test_wrong_role_cli_stops_before_subprocess_or_network(self):
        cfg = Path(self.temporary.name) / "config.json"
        cfg.write_text(json.dumps(REMOTE_CONFIG))
        with patch.dict(os.environ, {"RS_LAB_CONFIG": str(cfg)}), patch.object(
            sys, "argv", ["probe.py", "positive"]
        ), patch.object(probe.subprocess, "run") as run, patch.object(
            probe.socket, "socket"
        ) as create, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                probe.main()
        run.assert_not_called()
        create.assert_not_called()


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.row = {"fixture": "azure-routeserver-origin-v1", "case_id": "case",
                    "server_ip": "172.20.50.10", "server_port": 8080,
                    "peer_ip": "10.255.1.1", "peer_port": 45679, "path": "/probe"}

    def matches(self, expected_node="either"):
        return probe.identity(self.row, "case", 8080, "/probe", expected_node)

    def test_nva1_expected_node(self):
        self.assertTrue(self.matches("nva1"))
        self.assertFalse(self.matches("nva2"))
        self.assertTrue(self.matches())

    def test_nva2_expected_node(self):
        self.row["peer_ip"] = "10.255.2.1"
        self.assertTrue(self.matches("nva2"))
        self.assertFalse(self.matches("nva1"))
        self.assertTrue(self.matches())

    def test_original_source_is_not_expected_remote_identity(self):
        self.row["peer_ip"] = "10.10.1.10"
        self.assertFalse(self.matches())

    def test_actual_q_need_not_equal_client_a(self):
        self.row["peer_port"] = 60000
        self.assertTrue(self.matches())

    def test_bad_port_and_malformed_source_rejected(self):
        for value in (0, 65536, True, "45679", None):
            self.row["peer_port"] = value
            self.assertFalse(self.matches())
        self.row["peer_port"] = 45679
        self.row["peer_ip"] = []
        self.assertFalse(self.matches())

    def test_wrong_fixture_and_destination_rejected(self):
        for field, value in (("fixture", "azure-nva-origin-v1"), ("server_ip", "10.30.1.20"),
                             ("case_id", "other"), ("path", "/health")):
            row = {**self.row, field: value}
            self.assertFalse(probe.identity(row, "case", 8080, "/probe"))


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.addresses = [
            {"ifname": "lo", "addr_info": [{"local": "172.20.50.10", "prefixlen": 32}]},
            {"ifname": "eth0", "addr_info": [{"local": "10.30.1.20", "prefixlen": 24}]},
        ]
        self.commands = []

    def readonly(self, command):
        self.commands.append(command)
        return subprocess.CompletedProcess(command, 0, json.dumps(self.addresses), "")

    def test_local_only_checks_both_units_and_listeners(self):
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request", side_effect=lambda port, case: {"port": port, "case": case}
        ) as request:
            result = fixture.check_local_ready(REMOTE_CONFIG)
        self.assertEqual(result["status"], "LOCAL_FIXTURES_READY")
        self.assertIn("no end-to-end", result["scope"])
        self.assertEqual([call.args[0] for call in request.call_args_list], [8080, 8081])
        self.assertEqual(self.commands[1:], [
            ["systemctl", "is-active", "azure-routeserver-fixture@8080.service"],
            ["systemctl", "is-active", "azure-routeserver-fixture@8081.service"],
        ])

    def test_d_on_physical_nic_is_not_loopback_readiness(self):
        self.addresses[0]["ifname"] = "eth1"
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request"
        ) as request:
            with self.assertRaisesRegex(ValueError, "loopback"):
                fixture.check_local_ready(REMOTE_CONFIG)
        request.assert_not_called()

    def test_d_wrong_prefix_rejected(self):
        self.addresses[0]["addr_info"][0]["prefixlen"] = 24
        with patch.object(fixture, "run_readonly", side_effect=self.readonly):
            with self.assertRaisesRegex(ValueError, "loopback"):
                fixture.check_local_ready(REMOTE_CONFIG)

    def test_underlay_address_required(self):
        self.addresses.pop()
        with patch.object(fixture, "run_readonly", side_effect=self.readonly):
            with self.assertRaisesRegex(ValueError, "underlay"):
                fixture.check_local_ready(REMOTE_CONFIG)

    def test_remote_wrong_role_before_commands(self):
        with patch.object(fixture, "run_readonly") as run:
            with self.assertRaises(ValueError):
                fixture.check_local_ready(CONFIG)
        run.assert_not_called()

    def test_inactive_listener_is_not_ready(self):
        def run(command):
            if "systemctl" == command[0]:
                raise subprocess.CalledProcessError(3, command)
            return self.readonly(command)
        with patch.object(fixture, "run_readonly", side_effect=run), patch.object(
            fixture, "ready_request"
        ) as request:
            with self.assertRaises(subprocess.CalledProcessError):
                fixture.check_local_ready(REMOTE_CONFIG)
        request.assert_not_called()

    def test_failed_8081_listener_is_not_ready(self):
        with patch.object(fixture, "run_readonly", side_effect=self.readonly), patch.object(
            fixture, "ready_request", side_effect=[{"port": 8080}, TimeoutError("mock fixture down")]
        ):
            with self.assertRaises(TimeoutError):
                fixture.check_local_ready(REMOTE_CONFIG)

    def test_fixed_config_rejects_changed_addresses(self):
        for key in ("private_ip", "app_ip", "destination_ip", "remote_ip"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                fixture.validate_remote_config({**REMOTE_CONFIG, key: "127.0.0.1"})
        for key in ("private_ip", "app_ip", "destination_ip", "remote_ip"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                probe.validate_app_config({**CONFIG, key: "127.0.0.1"})


class BoundedFailureTests(unittest.TestCase):
    """Real sockets bind ONLY to loopback and short deadlines replace production limits."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.out = Path(self.temporary.name)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(3)
        self.port = self.listener.getsockname()[1]
        self.accepts = []
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
                    conn.recv(4096)
                    write(conn)
            except OSError:
                pass
        self.thread = threading.Thread(target=target, daemon=True)
        self.thread.start()

    def perform(self, stream=False):
        with patch.object(probe, "DESTINATION_IP", "127.0.0.1"), patch.dict(
            probe.OVERLAY_PEERS, {"nva1": "127.0.0.1", "nva2": "127.0.0.2"}, clear=True
        ):
            return probe.perform("127.0.0.1", self.port, "bounded-case", stream,
                                 5, self.out, source="127.0.0.1", expected_node="nva1")

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

    def test_total_deadline_also_works_outside_main_thread(self):
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
            row = {"fixture": "azure-routeserver-origin-v1", "case_id": "bounded-case",
                   "server_ip": "127.0.0.1", "server_port": self.port,
                   "peer_ip": "127.0.0.1", "peer_port": self.accepts[0][1],
                   "path": "/stream", "frame": 0}
            conn.sendall(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" +
                         (json.dumps(row) + "\n").encode())
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
