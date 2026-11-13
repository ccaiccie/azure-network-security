#!/usr/bin/env bash
# INSIDE the named VM. Checks owned services, sockets and exact fixed JSON response.
# No package installation; no external requests. Nonzero means not ready.
set -euo pipefail
exec python3 - "${EW_LAB_CONFIG:-/etc/azure-ew-lab.json}" <<'PY'
import json
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.request import ProxyHandler, build_opener

config = json.load(open(sys.argv[1], encoding="utf-8"))
role, address, ports = config["role"], config["private_ip"], config["listen_ports"]
print("Readiness UTC", datetime.now(timezone.utc).isoformat(), "role", role, flush=True)
if role not in ("app", "db", "c") or ports != ([8080] if role == "app" else [8080, 8081]):
    raise SystemExit("Invalid fixture role or expected port list")
addresses = subprocess.run(["ip", "-4", "-o", "addr", "show"], check=True, text=True, capture_output=True).stdout
if f" {address}/" not in addresses:
    raise SystemExit(f"Wrong machine: expected local address {address}")
print(subprocess.run(["ss", "-lnt"], check=True, text=True, capture_output=True).stdout)
opener = build_opener(ProxyHandler({}))
for port in ports:
    service = f"azure-ew-fixture@{port}.service"
    result = subprocess.run(["systemctl", "is-active", service], text=True, capture_output=True)
    print(service, result.stdout.strip(), result.stderr.strip(), flush=True)
    if result.returncode != 0:
        raise SystemExit(f"NOT READY: owned service {service} is not active")
    error = None
    for attempt in range(10):
        try:
            with opener.open(f"http://{address}:{port}/ready-local", timeout=2) as response:
                record = json.load(response)
                if response.status != 200:
                    raise ValueError("expected HTTP 200")
            if (record.get("fixture_role"), record.get("server_ip"), record.get("server_port"), record.get("peer_ip")) != (role, address, port, address):
                raise ValueError("wrong fixture identity or local source")
            print(json.dumps(record, sort_keys=True), flush=True)
            error = None
            break
        except (OSError, ValueError) as exc:
            error = exc
            time.sleep(1)
    if error is not None:
        raise SystemExit(f"NOT READY: local {address}:{port}: {error}")
print("LOCAL_FIXTURES_READY: local service readiness only, not remote/firewall validation", flush=True)
PY
