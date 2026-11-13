#!/usr/bin/env python3
"""One bounded direct HTTP connection from A to D. No DNS/proxy/retry/reconnect."""

import argparse
import http.client
import ipaddress
import json
import os
import re
import secrets
import socket
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

APP_IP = "10.10.1.10"
DESTINATION_IP = "172.20.50.10"
REMOTE_IP = "10.30.1.20"
FIXTURE_ID = "azure-routeserver-origin-v1"
OVERLAY_PEERS = {"nva1": "10.255.1.1", "nva2": "10.255.2.1"}
SOCKET_TIMEOUT_SECONDS = 5
FRESH_TOTAL_SECONDS = 15
STREAM_GRACE_SECONDS = 10


def utc():
    return datetime.now(timezone.utc).isoformat()


def new_out(requested, case):
    out = Path(requested) if requested else Path.home() / "rs-evidence" / case
    out.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive directory creation also rejects files and symlinks at this path.
    out.mkdir(mode=0o700, exist_ok=False)
    return out


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)


def expected_peers(expected_node):
    if expected_node == "either":
        return set(OVERLAY_PEERS.values())
    if expected_node not in OVERLAY_PEERS:
        raise ValueError("expected_node must be nva1, nva2 or either")
    return {OVERLAY_PEERS[expected_node]}


def identity(row, case, port, path, expected_node="either"):
    if not isinstance(row, dict):
        return False
    return (
        tuple(row.get(key) for key in ("fixture", "case_id", "server_ip", "server_port", "path"))
        == (FIXTURE_ID, case, DESTINATION_IP, port, path)
        and isinstance(row.get("peer_ip"), str)
        and row.get("peer_ip") in expected_peers(expected_node)
        and type(row.get("peer_port")) is int
        and 1 <= row["peer_port"] <= 65535
    )


class TotalDeadline:
    """A wall-clock socket cutoff, also effective outside the main Python thread."""

    def __init__(self, sock, seconds):
        self.sock = sock
        self.deadline = time.monotonic() + seconds
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
        remaining = self.deadline - time.monotonic()
        if self.expired.is_set() or remaining <= 0:
            raise TimeoutError("Total bounded client window exceeded")

    def start(self):
        self.timer.start()

    def stop(self):
        self.timer.cancel()
        self.timer.join()


def perform(host, port, case, stream, duration, out, source=None, expected_node="either"):
    """Internal socket probe; the CLI separately enforces the fixed lab scope."""
    if not 5 <= duration <= 180:
        raise ValueError("duration must be 5..180 seconds")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", case):
        raise ValueError("Invalid case ID")
    if ipaddress.ip_address(host).version != 4:
        raise ValueError("Destination must be a literal IPv4 address")
    if source is not None and ipaddress.ip_address(source).version != 4:
        raise ValueError("Source must be a literal IPv4 address")
    peers = expected_peers(expected_node)
    start = time.monotonic()
    total_seconds = duration + STREAM_GRACE_SECONDS if stream else FRESH_TOTAL_SECONDS
    result = {
        "started_utc": utc(), "case_id": case, "mode": "stream" if stream else "fresh",
        "duration_requested": duration if stream else None,
        "outcome": "NEEDS_REVIEW", "attempted_destination": [host, port],
        "tcp_connect_completed": False, "request_write_status": "not-started",
        "http_request_not_sent": True, "expected_node": expected_node,
        "expected_fixture_peer_ips": sorted(peers),
        "socket_timeout_seconds": SOCKET_TIMEOUT_SECONDS, "total_timeout_seconds": total_seconds,
        "automatic_reconnect": False, "frames_received": 0, "stream_complete": False,
        "evidence_note": "Correlate actual Azure routes, both NVAs' counters/conntrack/captures and remote journal. A timeout alone does not prove policy.",
    }
    frames = []
    first_frame_at = None
    response = None
    reached_eof = False
    cutoff = None
    conn = http.client.HTTPConnection(host, port, timeout=SOCKET_TIMEOUT_SECONDS)
    # A request is only issued on our one explicitly connected socket.
    conn.auto_open = 0
    try:
        conn.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock.settimeout(SOCKET_TIMEOUT_SECONDS)
        cutoff = TotalDeadline(conn.sock, total_seconds)
        cutoff.start()
        cutoff.check()
        conn.sock.bind((source or "0.0.0.0", 0))
        result["attempted_local"] = list(conn.sock.getsockname())
        result["client_local"] = result["attempted_local"]
        result["connect_attempt_utc"] = utc()
        # The original local ephemeral port is durable BEFORE any SYN/connect.
        write_json(out / "connection.json", result)
        cutoff.check()
        conn.sock.connect((host, port))
        result["tcp_connect_completed"] = True
        result["connected_utc"] = utc()
        result["client_local"] = list(conn.sock.getsockname())
        result["client_remote"] = list(conn.sock.getpeername())
        write_json(out / "connection.json", result)
        path = f"/stream?seconds={duration}" if stream else "/probe"
        cutoff.check()
        result["request_write_status"] = "attempting"
        # A failed send may have written some bytes; never label it HTTP-not-sent.
        result["http_request_not_sent"] = False
        conn.request("GET", path, headers={
            "X-Lab-Case-ID": case, "User-Agent": "azure-routeserver-lab/" + case,
            "Connection": "close",
        })
        result["request_write_status"] = "completed-not-proof-of-delivery"
        cutoff.check()
        response = conn.getresponse()
        result["http_status"] = response.status
        result["response_headers"] = dict(response.getheaders())
        with (out / "frames.ndjson").open("x") as output:
            while True:
                cutoff.check()
                line = response.readline(8193)
                cutoff.check()
                if not line:
                    reached_eof = True
                    break
                if len(line) > 8192:
                    raise ValueError("Oversized fixture frame")
                if len(frames) >= (duration + 3 if stream else 1):
                    raise ValueError("Too many fixture frames")
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError("Fixture frame must be a JSON object")
                if first_frame_at is None:
                    first_frame_at = time.monotonic()
                frames.append(row)
                output.write(json.dumps(row) + "\n")
                output.flush()
    except (OSError, ValueError, http.client.HTTPException, TimeoutError) as exc:
        result["error_type"] = "TimeoutError" if cutoff and cutoff.expired.is_set() else type(exc).__name__
        result["error"] = "Total bounded client window exceeded" if cutoff and cutoff.expired.is_set() else str(exc)
    except BaseException as exc:
        result["error_type"] = type(exc).__name__
        result["error"] = "Probe interrupted; no reconnect attempted"
        raise
    finally:
        if cutoff is not None:
            cutoff.stop()
        if response is not None:
            response.close()
        conn.close()
        result["frames_received"] = len(frames)
        observed = {(row.get("peer_ip"), row.get("peer_port")) for row in frames
                    if isinstance(row.get("peer_ip"), str) and type(row.get("peer_port")) is int}
        result["observed_fixture_peer_tuples"] = [list(peer) for peer in sorted(observed)]
        result["observed_nodes"] = sorted({name for name, ip in OVERLAY_PEERS.items()
                                            if any(peer[0] == ip for peer in observed)})
        result["fixture_identity"] = "MATCH" if (
            result.get("http_status") == 200 and frames and len(observed) == 1
            and all(identity(row, case, port, "/stream" if stream else "/probe", expected_node)
                    for row in frames)
        ) else "MISMATCH" if frames else "UNOBSERVED"
        result["last_frame_utc"] = frames[-1].get("time_utc") if frames else None
        result["fixture_response_complete"] = reached_eof and "error" not in result
        result["stream_complete"] = bool(
            stream and result["fixture_response_complete"] and result["fixture_identity"] == "MATCH"
            and frames[-1].get("stream_end") is True
            and all(row.get("stream_end") is not True for row in frames[:-1])
            and all(type(row.get("frame")) is int for row in frames)
            and [row.get("frame") for row in frames] == list(range(len(frames)))
            and first_frame_at is not None and time.monotonic() - first_frame_at >= duration - 1
        )
        if len(observed) == 1 and result.get("client_local"):
            result["source_port_preserved_observed"] = next(iter(observed))[1] == result["client_local"][1]
        result["completed_utc"] = utc()
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        write_json(out / "result.json", result)
    return result


def validate_app_config(config):
    required = {"role": "app", "private_ip": APP_IP, "app_ip": APP_IP,
                "destination_ip": DESTINATION_IP, "remote_ip": REMOTE_IP}
    if any(config.get(key) != value for key, value in required.items()):
        raise ValueError("Run only on the declared fixed-address app VM")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=["positive", "negative", "stream"])
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--out")
    parser.add_argument("--expected-node", choices=["nva1", "nva2", "either"], default="either")
    args = parser.parse_args()
    if not 5 <= args.duration <= 180:
        parser.error("duration must be 5..180 seconds")
    try:
        config = json.loads(Path(os.environ.get("RS_LAB_CONFIG", "/etc/azure-routeserver-lab.json")).read_text())
        validate_app_config(config)
        addresses = json.loads(subprocess.run(["ip", "-j", "-4", "addr", "show"], check=True,
                                              capture_output=True, text=True, timeout=5).stdout)
        if not any(any(addr.get("local") == APP_IP for addr in item.get("addr_info", []))
                   for item in addresses):
            raise ValueError("Expected local A address absent")
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    case = "rs-" + args.case + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)
    try:
        out = new_out(args.out, case)
    except OSError as exc:
        parser.error("Use a NEW nonexistent evidence directory: " + str(exc))
    result = perform(DESTINATION_IP, 8081 if args.case == "negative" else 8080,
                     case, args.case == "stream", args.duration, out, source=APP_IP,
                     expected_node=args.expected_node)
    result["requested_case"] = args.case
    write_json(out / "result.json", result)
    print(json.dumps(result, indent=2))
    print("RESULT=NEEDS_REVIEW; a timeout is not proof of policy. Evidence:", out)


if __name__ == "__main__":
    main()
