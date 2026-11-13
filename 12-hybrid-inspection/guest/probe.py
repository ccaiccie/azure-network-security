#!/usr/bin/env python3
"""One bounded source-preserving TCP/HTTP attempt. No DNS/proxy/retry/reconnect."""

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

BRANCH_IP = "172.16.10.10"
SPOKE_IP = "10.20.1.20"
FIXTURE_ID = "azure-hybrid-fixture-v1"
SOCKET_TIMEOUT_SECONDS = 5
FRESH_TOTAL_SECONDS = 15
STREAM_GRACE_SECONDS = 10
MODES = ("closed", "positive", "alternate", "reverse", "stream")


def utc():
    return datetime.now(timezone.utc).isoformat()


def new_out(requested, case):
    out = Path(requested) if requested else Path.home() / "hybrid-evidence" / case
    out.parent.mkdir(parents=True, exist_ok=True)
    out.mkdir(mode=0o700, exist_ok=False)  # Reject pre-existing files/directories/symlinks.
    return out


def write_json(path, value):
    """Write each evidence snapshot once, durably, without replacing prior evidence."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w") as output:
        output.write(json.dumps(value, indent=2) + "\n")
        output.flush()
        os.fsync(output.fileno())


def identity(row, case, host, port, path, source, source_port):
    if not isinstance(row, dict):
        return False
    return (
        tuple(row.get(key) for key in (
            "fixture", "case_id", "server_ip", "server_port", "path", "peer_ip", "peer_port"
        )) == (FIXTURE_ID, case, host, port, path, source, source_port)
        and type(row.get("server_port")) is int
        and type(row.get("peer_port")) is int
        and 1 <= row["peer_port"] <= 65535
    )


class TotalDeadline:
    """Socket shutdown limits slow headers/body, including non-main-thread use."""

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
        if self.expired.is_set() or time.monotonic() >= self.deadline:
            raise TimeoutError("Total bounded client window exceeded")

    def start(self):
        self.timer.start()

    def stop(self):
        self.timer.cancel()
        self.timer.join()


def perform(host, port, case, stream, duration, out, source, mode=None):
    """Internal numeric socket helper; CLI enforces the fixed lab role/tuple scope."""
    if type(duration) is not int or not 5 <= duration <= 180:
        raise ValueError("duration must be 5..180 seconds")
    if not isinstance(case, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", case):
        raise ValueError("Invalid case ID")
    if ipaddress.ip_address(host).version != 4 or ipaddress.ip_address(source).version != 4:
        raise ValueError("Source and destination must be literal IPv4 addresses")
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("Invalid port")
    if mode is None:
        mode = "stream" if stream else "positive"
    if mode not in MODES or (mode == "stream") != bool(stream):
        raise ValueError("Invalid mode or stream selection")
    out = Path(out)
    start = time.monotonic()
    total_seconds = duration + STREAM_GRACE_SECONDS if stream else FRESH_TOTAL_SECONDS
    result = {
        "started_utc": utc(), "case_id": case, "mode": mode, "requested_case": mode,
        "duration_requested": duration if stream else None, "outcome": "NEEDS_REVIEW",
        "attempted_destination": [host, port], "attempted_source_ip": source,
        "tcp_connect_completed": False, "request_write_status": "not-started",
        "http_request_not_sent": True, "expected_fixture": FIXTURE_ID,
        "expected_source_preserved": True,
        "socket_timeout_seconds": SOCKET_TIMEOUT_SECONDS, "total_timeout_seconds": total_seconds,
        "automatic_retry": False, "automatic_reconnect": False,
        "frames_received": 0, "stream_complete": False,
        "fixture_identity": "UNOBSERVED", "fixture_response_complete": False,
        "source_tuple_preserved_observed": False,
        "evidence_note": "Correlate exact tuples and UTC with healthy fixtures, actual NIC, GatewaySubnet and firewall onward routes, installed rules and AZFWNetworkRule rows. A timeout alone does not prove firewall inspection or denial.",
    }
    frames = []
    first_frame_at = None
    last_frame_at = None
    response = None
    reached_eof = False
    cutoff = None
    conn = http.client.HTTPConnection(host, port, timeout=SOCKET_TIMEOUT_SECONDS)
    conn.auto_open = 0  # Never open a replacement socket when the single connection fails.
    try:
        conn.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock.settimeout(SOCKET_TIMEOUT_SECONDS)
        cutoff = TotalDeadline(conn.sock, total_seconds)
        cutoff.start()
        cutoff.check()
        conn.sock.bind((source, 0))
        result["attempted_local"] = list(conn.sock.getsockname())
        result["connect_attempt_utc"] = utc()
        # Immutable and fsynced BEFORE SYN, including for intentionally denied flows.
        write_json(out / "connection.json", result)
        cutoff.check()
        conn.sock.connect((host, port))
        result["tcp_connect_completed"] = True
        result["connected_utc"] = utc()
        result["client_local"] = list(conn.sock.getsockname())
        result["client_remote"] = list(conn.sock.getpeername())
        write_json(out / "connected.json", result)
        if result["client_local"] != result["attempted_local"] or result["client_remote"] != [host, port]:
            raise ValueError("Actual connected socket tuple differs from attempted tuple")
        path = f"/stream?seconds={duration}" if stream else "/probe"
        cutoff.check()
        result["request_write_status"] = "attempting"
        # From here a failed send may be partial; never claim HTTP was not sent.
        result["http_request_not_sent"] = False
        result["request_write_started_utc"] = utc()
        write_json(out / "request-started.json", result)
        conn.request("GET", path, headers={
            "X-Lab-Case-ID": case, "User-Agent": "azure-hybrid-lab/" + case,
            "Connection": "close",
        })
        result["request_write_status"] = "completed-not-proof-of-delivery"
        result["request_write_completed_utc"] = utc()
        write_json(out / "request-written.json", result)
        cutoff.check()
        response = conn.getresponse()
        result["http_status"] = response.status
        result["response_headers"] = dict(response.getheaders())
        with (out / "frames.ndjson").open("x") as output:
            os.chmod(out / "frames.ndjson", 0o600)
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
                last_frame_at = time.monotonic()
                frames.append(row)
                output.write(json.dumps(row) + "\n")
                output.flush()
    except (OSError, ValueError, http.client.HTTPException) as exc:
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
        source_port = result.get("attempted_local", [None, None])[1]
        result["fixture_identity"] = "MATCH" if (
            result.get("http_status") == 200 and frames
            and all(identity(row, case, host, port, "/stream" if stream else "/probe", source, source_port)
                    for row in frames)
        ) else "MISMATCH" if frames else "UNOBSERVED"
        result["source_tuple_preserved_observed"] = bool(
            frames and len(observed) == 1 and next(iter(observed)) == (source, source_port)
        )
        result["last_frame_utc"] = frames[-1].get("time_utc") if frames else None
        result["fixture_response_complete"] = reached_eof and "error" not in result
        result["stream_complete"] = bool(
            stream and result["fixture_response_complete"] and result["fixture_identity"] == "MATCH"
            and frames[-1].get("stream_end") is True
            and all(row.get("stream_end") is not True for row in frames[:-1])
            and all(type(row.get("frame")) is int for row in frames)
            and [row.get("frame") for row in frames] == list(range(len(frames)))
            and first_frame_at is not None and last_frame_at - first_frame_at >= duration - 1
        )
        result["completed_utc"] = utc()
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        write_json(out / "result.json", result)
    return result


def validate_config(config, mode):
    if mode not in MODES or not isinstance(config, dict) or set(config) != {"role", "private_ip", "branch_ip", "spoke_ip"}:
        raise ValueError("Invalid lab configuration or mode")
    reverse = mode == "reverse"
    role, source = ("spoke", SPOKE_IP) if reverse else ("branch", BRANCH_IP)
    required = {"role": role, "private_ip": source, "branch_ip": BRANCH_IP, "spoke_ip": SPOKE_IP}
    if any(config.get(key) != value for key, value in required.items()):
        raise ValueError(f"Mode {mode} requires the declared fixed-address {role} VM")
    return source, BRANCH_IP if reverse else SPOKE_IP, 8082 if reverse else 8081 if mode == "alternate" else 8080


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=MODES)
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--out")
    args = parser.parse_args()
    if not 5 <= args.duration <= 180:
        parser.error("duration must be 5..180 seconds")
    try:
        config = json.loads(Path(os.environ.get("HYBRID_LAB_CONFIG", "/etc/azure-hybrid-lab.json")).read_text())
        source, host, port = validate_config(config, args.case)
        addresses = json.loads(subprocess.run(["ip", "-j", "-4", "addr", "show"], check=True,
                                              capture_output=True, text=True, timeout=5).stdout)
        if not isinstance(addresses, list) or not any(
            isinstance(item, dict) and item.get("ifname") not in (None, "lo")
            and any(addr.get("local") == source for addr in item.get("addr_info", [])
                    if isinstance(addr, dict)) for item in addresses
        ):
            raise ValueError("Expected fixed source address is absent from a local non-loopback NIC")
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    case = "hybrid-" + args.case + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)
    try:
        out = new_out(args.out, case)
    except OSError as exc:
        parser.error("Use a NEW nonexistent evidence directory: " + str(exc))
    result = perform(host, port, case, args.case == "stream", args.duration, out, source, mode=args.case)
    print(json.dumps(result, indent=2))
    print("RESULT=NEEDS_REVIEW; a timeout is not proof of firewall inspection or denial. Evidence:", out)


if __name__ == "__main__":
    main()
