#!/usr/bin/env python3
"""Private synthetic origin. Fixed JSON and finite streams, no file serving."""

import argparse
import http.client
import json
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
DESTINATION_IP = "172.20.50.10"
REMOTE_IP = "10.30.1.20"
FIXTURE_ID = "azure-routeserver-origin-v1"
SERVICE_PREFIX = "azure-routeserver-fixture"
MAX_REQUEST_SECONDS = 195


def utc():
    return datetime.now(timezone.utc).isoformat()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        # Every request closes the connection; streams never reconnect or redirect.
        self.close_connection = True
        if len(self.path) > 256:
            self.send_error(414)
            return
        if sum(len(key) + len(value) for key, value in self.headers.items()) > 8192:
            self.send_error(431)
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
                if set(query) != {"seconds"} or len(query["seconds"]) != 1 or target.fragment:
                    raise ValueError("Expected a single seconds parameter")
                duration = int(query["seconds"][0])
                if not 5 <= duration <= 180 or self.server.server_address[1] not in (
                    8080, getattr(self.server, "test_port", -1)
                ):
                    raise ValueError("Unsupported stream duration or service")
            except (ValueError, KeyError):
                self.send_error(400)
                return
        elif self.path not in ("/probe", "/health"):
            self.send_error(404)
            return

        def row(frame):
            return {
                "fixture": FIXTURE_ID,
                "case_id": case,
                "time_utc": utc(),
                "frame": frame,
                "path": target.path,
                "peer_ip": self.client_address[0],
                "peer_port": self.client_address[1],
                "server_ip": self.server.server_address[0],
                "server_port": self.server.server_address[1],
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
        except (OSError, TimeoutError):
            # Closing a client socket during a failover experiment is expected.
            pass

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
        # Inactivity timeout alone does not bound a slow header sender.
        timer = threading.Timer(MAX_REQUEST_SECONDS, self.shutdown_request, args=(request,))
        timer.daemon = True
        timer.start()
        try:
            super().process_request_thread(request, address)
        finally:
            timer.cancel()
            self.slots.release()


def make_server(bind, port):
    """Internal constructor also permits ephemeral loopback ports for offline tests."""
    return BoundedServer((bind, port), Handler)


def validate_remote_config(config):
    required = {
        "role": "remote", "private_ip": REMOTE_IP, "app_ip": APP_IP,
        "destination_ip": DESTINATION_IP, "remote_ip": REMOTE_IP,
    }
    if any(config.get(key) != value for key, value in required.items()):
        raise ValueError("Run only on the declared fixed-address remote VM")


def run_readonly(command):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)


def ready_request(port, case):
    # Direct literal address and explicit source: never proxies, DNS, redirects or retries.
    conn = http.client.HTTPConnection(DESTINATION_IP, port, timeout=2,
                                      source_address=(DESTINATION_IP, 0))
    timer = None
    expired = threading.Event()
    try:
        conn.connect()  # Connect timeout is two seconds; no hostname lookup is needed.
        conn.auto_open = 0
        sock = conn.sock

        def expire():
            expired.set()
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            finally:
                sock.close()

        timer = threading.Timer(4, expire)
        timer.daemon = True
        timer.start()
        conn.request("GET", "/probe", headers={"X-Lab-Case-ID": case, "Connection": "close"})
        response = conn.getresponse()
        try:
            body = response.read(8193)
        finally:
            response.close()
        if expired.is_set():
            raise TimeoutError("Local readiness response exceeded four seconds")
        if response.status != 200 or len(body) > 8192:
            raise ValueError("Unexpected local fixture response")
        row = json.loads(body)
        expected = (FIXTURE_ID, case, DESTINATION_IP, port, DESTINATION_IP, "/probe")
        if not isinstance(row, dict) or tuple(row.get(key) for key in (
            "fixture", "case_id", "server_ip", "server_port", "peer_ip", "path"
        )) != expected:
            raise ValueError("Local fixture identity mismatch")
        return row
    finally:
        if timer is not None:
            timer.cancel()
            timer.join()
        conn.close()


def check_local_ready(config):
    """Read-only check. It does NOT verify GRE, BGP, Azure routes or app reachability."""
    validate_remote_config(config)
    addresses = json.loads(run_readonly(["ip", "-j", "-4", "addr", "show"]).stdout)
    if not any(item.get("ifname") == "lo" and any(
        addr.get("local") == DESTINATION_IP and addr.get("prefixlen") == 32
        for addr in item.get("addr_info", [])
    ) for item in addresses):
        raise ValueError("Required D /32 is absent from local loopback lo")
    if not any(item.get("ifname") != "lo" and any(
        addr.get("local") == REMOTE_IP for addr in item.get("addr_info", [])
    ) for item in addresses):
        raise ValueError("Required remote underlay address R is absent")
    observations = []
    for port in (8080, 8081):
        run_readonly(["systemctl", "is-active", f"{SERVICE_PREFIX}@{port}.service"])
        case = f"local-ready-{port}-{time.time_ns()}"
        observations.append(ready_request(port, case))
    return {
        "status": "LOCAL_FIXTURES_READY", "time_utc": utc(), "ports": [8080, 8081],
        "scope": "D loopback and both local units/listeners only; no end-to-end, GRE, BGP or failover claim",
        "observations": observations,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", choices=[DESTINATION_IP])
    parser.add_argument("--port", type=int, choices=[8080, 8081])
    parser.add_argument("--check-local-ready", action="store_true")
    parser.add_argument("--config", default="/etc/azure-routeserver-lab.json")
    args = parser.parse_args()
    if args.check_local_ready:
        if args.bind is not None or args.port is not None:
            parser.error("Readiness check cannot also start a listener")
        try:
            result = check_local_ready(json.loads(Path(args.config).read_text()))
        except (OSError, ValueError, subprocess.SubprocessError, http.client.HTTPException) as exc:
            raise SystemExit("LOCAL_FIXTURES_NOT_READY: " + str(exc)) from exc
        print(json.dumps(result, indent=2))
        return
    if args.bind is None or args.port is None:
        parser.error("Both --bind and --port are required to start the fixed listener")
    server = make_server(args.bind, args.port)
    print(json.dumps({"event": "listening", "fixture": FIXTURE_ID,
                      "bind": args.bind, "port": args.port, "time_utc": utc()}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
