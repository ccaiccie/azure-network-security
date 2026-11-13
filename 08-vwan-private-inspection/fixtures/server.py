#!/usr/bin/env python3
"""Fixed private synthetic HTTP fixtures; no filesystem or real-data serving."""

import argparse
import http.client
import json
import os
import re
import socket
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

APP_IP = "10.10.1.10"
BACKEND_IP = "10.20.1.20"
FIXTURE_ID = "azure-vwan-origin-v1"
SERVICE_PREFIX = "azure-vwan-fixture"
MAX_REQUEST_SECONDS = 195
MAX_HEADER_BYTES = 8192


def utc():
    return datetime.now(timezone.utc).isoformat()


class HeaderBudget:
    """Enforce an aggregate header-byte limit while the standard parser reads."""

    def __init__(self, reader):
        self.reader = reader
        self.remaining = MAX_HEADER_BYTES

    def readline(self, size=-1):
        limit = self.remaining + 1
        if size >= 0:
            limit = min(limit, size)
        line = self.reader.readline(limit)
        self.remaining -= len(line)
        if self.remaining < 0:
            raise http.client.LineTooLong("fixture headers")
        return line


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SyntheticFixture/1"
    sys_version = ""

    def parse_request(self):
        original = self.rfile
        self.rfile = HeaderBudget(original)
        try:
            return super().parse_request()
        finally:
            self.rfile = original

    def do_GET(self):
        self.close_connection = True
        if len(self.path) > 256:
            self.send_error(414)
            return
        if self.headers.get("Transfer-Encoding") is not None or self.headers.get("Content-Length") not in (None, "0"):
            self.send_error(400)
            return
        cases = self.headers.get_all("X-Lab-Case-ID", ["local-ready"])
        if len(cases) != 1 or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", cases[0]):
            self.send_error(400)
            return
        case = cases[0]
        target = urlsplit(self.path)
        duration = None
        if target.path == "/stream":
            query = parse_qs(target.query, keep_blank_values=True)
            try:
                if (set(query) != {"seconds"} or len(query["seconds"]) != 1
                        or "#" in self.path or target.scheme or target.netloc):
                    raise ValueError("Expected a single seconds parameter")
                if not re.fullmatch(r"[0-9]{1,3}", query["seconds"][0]):
                    raise ValueError("Expected integer seconds")
                duration = int(query["seconds"][0])
                if not 5 <= duration <= 180 or not self.server.stream_enabled:
                    raise ValueError("Unsupported stream duration or listener")
            except (ValueError, KeyError):
                self.send_error(400)
                return
        elif self.path not in ("/probe", "/health"):
            self.send_error(404)
            return

        def row(frame):
            local = self.connection.getsockname()
            return {
                "fixture": FIXTURE_ID, "case_id": case, "time_utc": utc(),
                "frame": frame, "path": target.path,
                "peer_ip": self.client_address[0], "peer_port": self.client_address[1],
                "server_ip": local[0], "server_port": local[1],
            }

        first = row(0)
        body = (json.dumps(first) + "\n").encode()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson" if duration else "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            if duration is None:
                self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            print(json.dumps(first), flush=True)
            if duration is not None:
                deadline = time.monotonic() + duration
                frame = 1
                while time.monotonic() < deadline:
                    time.sleep(min(1, max(0, deadline - time.monotonic())))
                    current = row(frame)
                    current["stream_end"] = time.monotonic() >= deadline
                    self.wfile.write((json.dumps(current) + "\n").encode())
                    self.wfile.flush()
                    print(json.dumps(current), flush=True)
                    frame += 1
        except OSError:
            pass  # Interrupted streams are observations, never retried.

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
        self.stream_enabled = self.server_address == (BACKEND_IP, 8080)

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
        # A timer also bounds peers that trickle headers without an idle timeout.
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
    """Internal constructor permits ephemeral loopback listeners for offline tests."""
    return BoundedServer((bind, port), Handler)


def validate_config(config):
    if not isinstance(config, dict):
        raise ValueError("Lab configuration must be a JSON object")
    role = config.get("role")
    private = {"app": APP_IP, "backend": BACKEND_IP}.get(role) if isinstance(role, str) else None
    required = {"app_ip": APP_IP, "backend_ip": BACKEND_IP, "private_ip": private}
    if private is None or any(config.get(key) != value for key, value in required.items()):
        raise ValueError("Expected declared app/backend role and fixed lab addresses")
    return role, private, (8082,) if role == "app" else (8080, 8081)


def run_readonly(command):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)


def validate_local_nic(private):
    addresses = json.loads(run_readonly(["ip", "-j", "-4", "addr", "show"]).stdout)
    if not isinstance(addresses, list) or not any(
        isinstance(item, dict) and item.get("ifname") not in (None, "lo")
        and any(addr.get("local") == private for addr in item.get("addr_info", [])
                if isinstance(addr, dict)) for item in addresses
    ):
        raise ValueError("Expected fixed private address is absent from a local non-loopback NIC")


def ready_request(private, port, case):
    """One source-bound numeric local HTTP request; no DNS/proxy/retry/redirect."""
    conn = http.client.HTTPConnection(private, port, timeout=2)
    conn.auto_open = 0
    timer = None
    expired = threading.Event()
    response = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock = sock
        sock.settimeout(2)
        sock.bind((private, 0))
        local = sock.getsockname()

        def expire():
            expired.set()
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            finally:
                sock.close()

        timer = threading.Timer(5, expire)
        timer.daemon = True
        timer.start()
        sock.connect((private, port))
        conn.request("GET", "/health", headers={
            "X-Lab-Case-ID": case, "User-Agent": "azure-vwan-ready/" + case,
            "Connection": "close",
        })
        response = conn.getresponse()
        body = response.read(8193)
        if expired.is_set():
            raise TimeoutError("Local readiness exceeded five seconds")
        if response.status != 200 or len(body) > 8192:
            raise ValueError("Unexpected local fixture response")
        row = json.loads(body)
        expected = (FIXTURE_ID, case, private, port, private, local[1], "/health")
        if not isinstance(row, dict) or tuple(row.get(key) for key in (
            "fixture", "case_id", "server_ip", "server_port", "peer_ip", "peer_port", "path"
        )) != expected:
            raise ValueError("Local fixture identity or source tuple mismatch")
        return row
    finally:
        if timer is not None:
            timer.cancel()
            timer.join()
        if response is not None:
            response.close()
        conn.close()


def check_local_ready(config):
    """Read-only local unit/NIC/HTTP readiness; not proof of any Azure transit."""
    role, private, ports = validate_config(config)
    validate_local_nic(private)
    expected_units = {f"{SERVICE_PREFIX}@{port}.service" for port in ports}
    active_output = run_readonly([
        "systemctl", "list-units", "--type=service", "--state=active", "--no-legend",
        "--no-pager", f"{SERVICE_PREFIX}@*.service",
    ]).stdout
    active_units = {line.split()[0] for line in active_output.splitlines() if line.strip()}
    if active_units != expected_units:
        raise ValueError("Active fixture units differ from the exact declared-role set")
    observations = []
    for port in ports:
        run_readonly(["systemctl", "is-active", f"{SERVICE_PREFIX}@{port}.service"])
        case = f"local-ready-{port}-{time.time_ns()}"
        observations.append(ready_request(private, port, case))
    return {
        "status": "LOCAL_FIXTURES_READY", "time_utc": utc(), "role": role,
        "private_ip": private, "ports": list(ports), "active_units": sorted(active_units),
        "observations": observations,
        "scope": "Declared local NIC, exact expected units and local HTTP identity only; no end-to-end routing, firewall or source-preservation claim",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, choices=[8080, 8081, 8082])
    parser.add_argument("--check-local-ready", action="store_true")
    parser.add_argument("--config", default=os.environ.get("VWAN_LAB_CONFIG", "/etc/azure-vwan-lab.json"))
    args = parser.parse_args()
    if args.check_local_ready and args.port is not None:
        parser.error("Readiness check cannot also start a listener")
    try:
        config = json.loads(Path(args.config).read_text())
        role, private, ports = validate_config(config)
        if args.check_local_ready:
            print(json.dumps(check_local_ready(config), indent=2))
            return
        if args.port not in ports:
            parser.error("App role requires port 8082; backend role requires port 8080 or 8081")
        validate_local_nic(private)
        server = make_server(private, args.port)
    except (OSError, ValueError, subprocess.SubprocessError, http.client.HTTPException) as exc:
        raise SystemExit("LOCAL_FIXTURE_ERROR: " + str(exc)) from exc
    print(json.dumps({"event": "listening", "fixture": FIXTURE_ID, "role": role,
                      "bind": private, "port": args.port, "time_utc": utc()}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
