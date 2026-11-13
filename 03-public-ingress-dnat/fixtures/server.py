#!/usr/bin/env python3
"""Synthetic DNAT HTTP fixture: no file serving, authentication or real data."""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def do_GET(self):
        if len(self.path) > 256:
            self.send_error(414)
            return
        record = {
            "time_utc": datetime.now(timezone.utc).isoformat(),
            "fixture_role": self.server.fixture_role,
            "case": self.path,
            "peer_ip": self.client_address[0],
            "peer_port": self.client_address[1],
            "server_ip": self.server.server_address[0],
            "server_port": self.server.server_address[1],
        }
        body = (json.dumps(record, sort_keys=True) + "\n").encode("utf-8")
        print(json.dumps(record, sort_keys=True), flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def log_message(self, format_string, *args):
        pass


def make_server(bind_ip, port, role):
    server = ThreadingHTTPServer((bind_ip, port), Handler)
    server.daemon_threads = True
    server.fixture_role = role
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", required=True)
    parser.add_argument("--port", required=True, type=int, choices=(8080,))
    parser.add_argument("--role", required=True, choices=("backend",))
    args = parser.parse_args()
    address = ipaddress.ip_address(args.bind)
    if address.version != 4 or not address.is_private or address.is_unspecified:
        parser.error("bind must be a specific private IPv4 address, never 0.0.0.0")
    server = make_server(args.bind, args.port, args.role)
    print(json.dumps({"event": "listening", "bind": args.bind, "port": args.port,
                      "role": args.role, "time_utc": datetime.now(timezone.utc).isoformat()}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
