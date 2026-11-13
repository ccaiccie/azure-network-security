#!/usr/bin/env python3
"""Fixed synthetic backend, independent application health, and local readiness.

Only this backend's numeric local addresses are contacted by readiness. The
external public client probe is separate; no backend-to-public test exists here.
"""

import argparse
import hashlib
import http.client
import json
import os
import re
import secrets
import socket
import socketserver
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

BACKEND_IP = "10.20.1.20"
FIXTURE_ID = "azure-gwlb-fixture-v1"
PORTS = (8080, 8081)
HEALTH_PORT = 8009
MAX_PAYLOAD_BYTES = 262144
MAX_HEADER_BYTES = 8192
MAX_REQUEST_SECONDS = 195
PAYLOAD_PATTERN = b"azure-gwlb-synthetic-payload-v1\n"
ROW_KEYS = {"fixture", "role", "case_id", "time_utc", "frame", "path", "purpose",
            "peer_ip", "peer_port", "server_ip", "server_port", "stream_end"}


def utc():
    return datetime.now(timezone.utc).isoformat()


def payload_body(size):
    if type(size) is not int or not 1 <= size <= MAX_PAYLOAD_BYTES:
        raise ValueError("payload bytes must be 1..262144")
    return (PAYLOAD_PATTERN * ((size + len(PAYLOAD_PATTERN) - 1) // len(PAYLOAD_PATTERN)))[:size]


def validate_config(config):
    if not isinstance(config, dict) or set(config) != {"backend_ip"} or config["backend_ip"] != BACKEND_IP:
        raise ValueError("Backend configuration must contain only backend_ip=10.20.1.20")
    return BACKEND_IP


def run_readonly(command):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)


def validate_local_nic(private):
    rows = json.loads(run_readonly(["ip", "-j", "-4", "addr", "show"]).stdout)
    if not isinstance(rows, list) or not any(
        isinstance(row, dict) and row.get("ifname") not in (None, "lo")
        and isinstance(row.get("addr_info"), list)
        and any(isinstance(address, dict) and address.get("local") == private
                for address in row["addr_info"]) for row in rows
    ):
        raise ValueError("Fixed backend address is absent from a local non-loopback NIC")


class Deadline:
    def __init__(self, sock, seconds):
        self.sock = sock
        self.end = time.monotonic() + seconds
        self.expired = threading.Event()
        self.timer = threading.Timer(seconds, self.expire)
        self.timer.daemon = True

    def expire(self):
        self.expired.set()
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        finally:
            self.sock.close()

    def check(self):
        if self.expired.is_set() or time.monotonic() >= self.end:
            raise TimeoutError("Local readiness exceeded its total bound")

    def start(self):
        self.timer.start()

    def stop(self):
        self.timer.cancel()
        self.timer.join()


class HeaderBudget:
    def __init__(self, reader):
        self.reader = reader
        self.remaining = MAX_HEADER_BYTES

    def readline(self, size=-1):
        limit = self.remaining + 1 if size < 0 else min(size, self.remaining + 1)
        line = self.reader.readline(limit)
        self.remaining -= len(line)
        if self.remaining < 0:
            raise http.client.LineTooLong("fixture aggregate headers")
        return line


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SyntheticGWLBFixture/1"
    sys_version = ""

    def parse_request(self):
        original = self.rfile
        self.rfile = HeaderBudget(original)
        try:
            return super().parse_request()
        finally:
            self.rfile = original

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        self.close_connection = True
        if len(self.path) > 256:
            self.send_error(414)
            return
        if self.headers.get("Transfer-Encoding") is not None or self.headers.get("Content-Length") not in (None, "0"):
            self.send_error(400)
            return
        try:
            target = urlsplit(self.path)
        except ValueError:
            self.send_error(400)
            return
        match = re.fullmatch(r"/(probe|stream|payload|health)/([A-Za-z0-9_.-]{1,128})", target.path)
        if not match or target.scheme or target.netloc or "#" in self.path:
            self.send_error(404)
            return
        endpoint, case = match.groups()
        if self.headers.get_all("X-Lab-Case-ID", []) != [case]:
            self.send_error(400)
            return
        # Local health is unmistakable in logs and cannot be mistaken for C traffic.
        if endpoint == "health" and (not case.startswith("local-ready-") or self.client_address[0] != self.connection.getsockname()[0]):
            self.send_error(403)
            return
        duration, size = None, None
        if endpoint in ("stream", "payload"):
            query = parse_qs(target.query, keep_blank_values=True)
            field, low, high = ("seconds", 5, 180) if endpoint == "stream" else ("bytes", 1, MAX_PAYLOAD_BYTES)
            try:
                if set(query) != {field} or len(query[field]) != 1 or not re.fullmatch(r"[0-9]{1,6}", query[field][0]):
                    raise ValueError("Expected one bounded numeric query parameter")
                value = int(query[field][0])
                if not low <= value <= high:
                    raise ValueError("Query parameter outside bounds")
                if endpoint == "stream":
                    duration = value
                else:
                    size = value
            except (ValueError, KeyError):
                self.send_error(400)
                return
        elif target.query or "?" in self.path:
            self.send_error(404)
            return

        def row(frame, stream_end=False):
            local = self.connection.getsockname()
            return {
                "fixture": FIXTURE_ID, "role": "backend", "case_id": case, "time_utc": utc(),
                "frame": frame, "path": target.path,
                "purpose": "local-readiness" if endpoint == "health" else "external-client-probe",
                "peer_ip": self.client_address[0], "peer_port": self.client_address[1],
                "server_ip": local[0], "server_port": local[1], "stream_end": stream_end,
            }

        first = row(0)
        body = payload_body(size) if size else (json.dumps(first, separators=(",", ":")) + "\n").encode()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream" if size else "application/x-ndjson")
            self.send_header("Connection", "close")
            for field in ("fixture", "role", "case_id", "server_ip", "server_port", "peer_ip", "peer_port", "path", "purpose"):
                self.send_header("X-Lab-" + field.replace("_", "-"), str(first[field]))
            if duration is None:
                self.send_header("Content-Length", str(len(body)))
                self.send_header("X-Lab-Body-SHA256", hashlib.sha256(body).hexdigest())
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            log = {**first, "response_body_bytes": len(body), "response_body_sha256": hashlib.sha256(body).hexdigest()}
            print(json.dumps(log), flush=True)
            if duration is not None:
                deadline = time.monotonic() + duration
                frame = 1
                while time.monotonic() < deadline:
                    time.sleep(min(1, max(0, deadline - time.monotonic())))
                    current = row(frame, time.monotonic() >= deadline)
                    encoded = (json.dumps(current, separators=(",", ":")) + "\n").encode()
                    self.wfile.write(encoded)
                    self.wfile.flush()
                    print(json.dumps({**current, "response_body_bytes": len(encoded), "response_body_sha256": hashlib.sha256(encoded).hexdigest()}), flush=True)
                    frame += 1
        except OSError:
            pass  # Finite stream loss is evidence, never a reason to reconnect.

    def do_POST(self):
        self.send_error(405)

    def log_message(self, *args):
        pass


class BoundedServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16
    allow_reuse_address = True

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(32)
        super().__init__(*args, **kwargs)

    def server_bind(self):
        # HTTPServer's default calls getfqdn(), potentially doing reverse DNS.
        # This fixture must start without any DNS or Internet dependency.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]

    def get_request(self):
        request, address = super().get_request()
        request.settimeout(5)
        return request, address

    def process_request(self, request, address):
        if not self.slots.acquire(False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        timer = threading.Timer(MAX_REQUEST_SECONDS, self.shutdown_request, args=(request,))
        timer.daemon = True
        timer.start()
        try:
            super().process_request_thread(request, address)
        finally:
            timer.cancel()
            timer.join()
            self.slots.release()


def make_server(bind, port):
    """Internal constructor allows ephemeral loopback ports only in offline tests."""
    return BoundedServer((bind, port), Handler)


def ready_request(private, port, case):
    """Exactly one source-bound local fixture GET, with no DNS or replacement socket."""
    conn = http.client.HTTPConnection(private, port, timeout=2)
    conn.auto_open = 0
    deadline = response = None
    try:
        conn.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock.settimeout(2)
        conn.sock.bind((private, 0))
        local = conn.sock.getsockname()
        deadline = Deadline(conn.sock, 5)
        deadline.start()
        conn.sock.connect((private, port))
        conn.request("GET", "/health/" + case, headers={
            "X-Lab-Case-ID": case, "Connection": "close", "Cache-Control": "no-store",
            "User-Agent": "azure-gwlb-local-readiness/1",
        })
        response = conn.getresponse()
        body = response.read(8193)
        deadline.check()
        if response.status != 200 or len(body) > 8192:
            raise ValueError("Local fixture did not return a bounded HTTP 200")
        row = json.loads(body)
        expected = (FIXTURE_ID, "backend", case, private, port, private, local[1], "/health/" + case, "local-readiness")
        if not isinstance(row, dict) or set(row) != ROW_KEYS or tuple(row.get(key) for key in (
            "fixture", "role", "case_id", "server_ip", "server_port", "peer_ip", "peer_port", "path", "purpose"
        )) != expected:
            raise ValueError("Local fixture identity or source tuple mismatch")
        return row
    finally:
        if deadline is not None:
            deadline.stop()
        if response is not None:
            response.close()
        conn.close()


def check_listeners(private):
    return [ready_request(private, port, f"local-ready-{port}-{secrets.token_hex(6)}") for port in PORTS]


def check_local_ready(config):
    private = validate_config(config)
    validate_local_nic(private)
    expected = {"azure-gwlb-fixture@8080.service", "azure-gwlb-fixture@8081.service", "azure-gwlb-app-health.service"}
    active = run_readonly(["systemctl", "list-units", "--type=service", "--state=active", "--no-legend", "--no-pager", "azure-gwlb-fixture@*.service", "azure-gwlb-app-health.service"]).stdout
    units = {line.split()[0] for line in active.splitlines() if line.strip()}
    if units != expected:
        raise ValueError("Active fixture and app-health units do not match the exact expected three units")
    for unit in sorted(expected):
        run_readonly(["systemctl", "is-active", unit])
    observations = check_listeners(private)
    return {"status": "LOCAL_APP_READY", "time_utc": utc(), "role": "backend", "backend_ip": private,
            "active_units": sorted(units), "fixture_ports": list(PORTS), "health_port": HEALTH_PORT,
            "observations": observations,
            "scope": "Exact local units, NIC and both synthetic fixture listeners only. Not a public client test or proof of GWLB path/policy."}


class HealthHandler(Handler):
    def do_GET(self):
        self.close_connection = True
        if self.path != "/health" or self.headers.get("Transfer-Encoding") is not None or self.headers.get("Content-Length") not in (None, "0"):
            self.send_error(404)
            return
        try:
            observations = check_listeners(self.server.backend_ip)
            body = json.dumps({"status": "LOCAL_FIXTURES_READY", "fixture": FIXTURE_ID,
                               "time_utc": utc(), "ports": [row["server_port"] for row in observations],
                               "scope": "Local application readiness only; not GWLB transit proof"}).encode()
            code = 200
        except (OSError, ValueError, http.client.HTTPException):
            body = json.dumps({"status": "LOCAL_FIXTURES_NOT_READY", "time_utc": utc()}).encode()
            code = 503
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
        except OSError:
            pass


def make_health_server(bind, port):
    server = BoundedServer((bind, port), HealthHandler)
    server.backend_ip = bind
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--port", type=int, choices=PORTS)
    mode.add_argument("--health", action="store_true")
    mode.add_argument("--check-local-ready", action="store_true")
    parser.add_argument("--config", default="/etc/azure-gwlb-app.json")
    args = parser.parse_args()
    try:
        config = json.loads(Path(args.config).read_text())
        private = validate_config(config)
        if args.check_local_ready:
            print(json.dumps(check_local_ready(config), indent=2))
            return
        validate_local_nic(private)
        server = make_health_server(private, HEALTH_PORT) if args.health else make_server(private, args.port)
    except (OSError, ValueError, subprocess.SubprocessError, http.client.HTTPException) as exc:
        raise SystemExit("LOCAL_APP_NOT_READY: " + str(exc)) from exc
    print(json.dumps({"event": "listening", "fixture": FIXTURE_ID, "role": "app-health" if args.health else "backend",
                      "bind": private, "port": HEALTH_PORT if args.health else args.port, "time_utc": utc()}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
