#!/usr/bin/env python3
"""One bounded source-bound forced egress TCP/HTTP attempt. No DNS/proxy/retry/reconnect."""

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

APP_IP = "10.20.1.10"
ORIGIN_IP = "10.50.1.20"
FIXTURE_ID = "azure-forced-origin-v1"
SOCKET_TIMEOUT_SECONDS = 5
FRESH_TOTAL_SECONDS = 15
STREAM_GRACE_SECONDS = 10
MODES = ("closed", "positive", "alternate", "perimeter", "stream")


def utc():
    return datetime.now(timezone.utc).isoformat()


def new_out(requested, case):
    out = Path(requested) if requested else Path.home() / "forced-evidence" / case
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


def public_ipv4(value, label):
    """Only canonical global unicast IPv4 literals, never DNS or special ranges."""
    if not isinstance(value, str):
        raise ValueError(label + " must be a numeric global IPv4 address")
    address = ipaddress.ip_address(value)
    if (address.version != 4 or str(address) != value or not address.is_global
            or address.is_multicast or address.is_reserved or address.is_unspecified
            or address.is_private or address.is_loopback or address.is_link_local
            or address in ipaddress.ip_network("192.0.0.0/24")
            or address in ipaddress.ip_network("192.88.99.0/24")):
        raise ValueError(label + " must be a numeric global unicast IPv4 address")
    return value


def validate_public_config(config, require_pool=False):
    expected = {"role", "private_ip", "app_ip", "origin_ip", "origin_public_ip", "egress_public_ips"}
    if not isinstance(config, dict) or set(config) != expected:
        raise ValueError("Configuration must contain exactly the six documented public fields")
    role = config.get("role")
    private = {"app": APP_IP, "origin": ORIGIN_IP}.get(role) if isinstance(role, str) else None
    if (private is None or config.get("private_ip") != private
            or config.get("app_ip") != APP_IP or config.get("origin_ip") != ORIGIN_IP):
        raise ValueError("Expected declared app/origin role and fixed lab addresses")
    destination = public_ipv4(config["origin_public_ip"], "origin_public_ip")
    pool = config["egress_public_ips"]
    if not isinstance(pool, list) or len(pool) > 1:
        raise ValueError("egress_public_ips must be a list of at most 1 public IPv4 address")
    for item in pool:
        public_ipv4(item, "egress_public_ips entry")
    if len(set(pool)) != len(pool) or destination in pool:
        raise ValueError("Egress pool must be unique and distinct from the origin public destination D")
    if require_pool and not pool:
        raise ValueError("A nonempty actual approved perimeter public P is required before a probe")
    return role, private, destination, tuple(pool)


def identity(row, case, origin_ip, port, path, egress_pool):
    """B reports observed public P:p. p may differ from the original client port a."""
    if not isinstance(row, dict):
        return False
    return (
        tuple(row.get(key) for key in (
            "fixture", "case_id", "server_ip", "server_port", "path"
        )) == (FIXTURE_ID, case, origin_ip, port, path)
        and type(row.get("server_port")) is int
        and isinstance(row.get("peer_ip"), str) and row["peer_ip"] in egress_pool
        and type(row.get("peer_port")) is int and 1 <= row["peer_port"] <= 65535
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


def perform(host, port, case, stream, duration, out, source, mode=None, *, origin_ip=ORIGIN_IP, egress_pool=()):
    """Internal numeric socket helper; CLI enforces global D/P and exact app A.

    Loopback-only tests use an explicit origin_ip and egress_pool override here.
    No internal override is exposed by the installed CLI.
    """
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
    if (ipaddress.ip_address(origin_ip).version != 4 or not isinstance(egress_pool, (list, tuple))
            or not egress_pool or any(ipaddress.ip_address(ip).version != 4 for ip in egress_pool)):
        raise ValueError("A literal IPv4 origin and nonempty expected public P are required")
    out = Path(out)
    start = time.monotonic()
    total_seconds = duration + STREAM_GRACE_SECONDS if stream else FRESH_TOTAL_SECONDS
    result = {
        "started_utc": utc(), "case_id": case, "mode": mode, "requested_case": mode,
        "duration_requested": duration if stream else None, "outcome": "NEEDS_REVIEW",
        "attempted_destination": [host, port], "attempted_source_ip": source,
        "tcp_connect_completed": False, "request_write_status": "not-started",
        "http_request_not_sent": True, "expected_fixture": FIXTURE_ID,
        "expected_source_preserved": False,
        "expected_origin_private": [origin_ip, port],
        "expected_egress_public_ips": list(egress_pool),
        "translation_model": "A:a -> D:d at client; Firewall may preserve A or SNAT to observed S:s; guest SNAT to private E:e; Azure maps E:e to public P:p; origin D:d maps separately to B:d; ports are observed, never assumed preserved",
        "socket_timeout_seconds": SOCKET_TIMEOUT_SECONDS, "total_timeout_seconds": total_seconds,
        "automatic_retry": False, "automatic_reconnect": False,
        "frames_received": 0, "stream_complete": False,
        "fixture_identity": "UNOBSERVED", "fixture_response_complete": False,
        "source_tuple_preserved_observed": False,
        "egress_translation_observed": False,
        "evidence_note": "Correlate A:a to D:d, observed pre-NAT source A or S, guest E:e, origin-observed P:p and B:d with UTC, healthy fixtures, Azure routes, Firewall logs and perimeter counters/conntrack. A timeout alone proves neither inspection nor denial. Azure public mappings are separate from guest SNAT.",
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
        if (len(result["attempted_local"]) != 2 or result["attempted_local"][0] != source
                or type(result["attempted_local"][1]) is not int
                or not 1 <= result["attempted_local"][1] <= 65535):
            raise ValueError("Bound socket did not report the exact requested source IP and valid ephemeral port")
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
            "X-Lab-Case-ID": case, "User-Agent": "azure-forced-lab/" + case,
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
            result.get("http_status") == 200 and frames and len(observed) == 1
            and all(identity(row, case, origin_ip, port, "/stream" if stream else "/probe", egress_pool)
                    for row in frames)
        ) else "MISMATCH" if frames else "UNOBSERVED"
        result["source_tuple_preserved_observed"] = bool(
            frames and len(observed) == 1 and next(iter(observed)) == (source, source_port)
        )
        result["observed_fixture_server_tuples"] = [list(server) for server in sorted({
            (row.get("server_ip"), row.get("server_port")) for row in frames
            if isinstance(row.get("server_ip"), str) and type(row.get("server_port")) is int
        })]
        result["egress_translation_observed"] = bool(
            result["fixture_identity"] == "MATCH" and len(observed) == 1
            and not result["source_tuple_preserved_observed"]
        )
        result["observed_translation"] = {
            "client_A_a": result.get("attempted_local"), "destination_D_p": [host, port],
            "origin_B_p": result["observed_fixture_server_tuples"],
            "egress_E_q": result["observed_fixture_peer_tuples"],
            "note": "Origin HTTP self-report is correlation evidence, not authenticated proof of an inspection path",
        }
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
    if mode not in MODES:
        raise ValueError("Invalid lab mode; reverse flow is not supported")
    role, source, destination, _pool = validate_public_config(config, require_pool=True)
    if role != "app":
        raise ValueError("Every public probe requires the declared fixed-address app VM")
    return source, destination, 8082 if mode == "perimeter" else 8081 if mode == "alternate" else 8080


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=MODES)
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--out")
    args = parser.parse_args()
    if not 5 <= args.duration <= 180:
        parser.error("duration must be 5..180 seconds")
    try:
        config = json.loads(Path(os.environ.get("FORCED_LAB_CONFIG", "/etc/azure-forced-lab.json")).read_text())
        source, host, port = validate_config(config, args.case)
        addresses = json.loads(subprocess.run(["ip", "-j", "-4", "addr", "show"], check=True,
                                              capture_output=True, text=True, timeout=5).stdout)
        if not isinstance(addresses, list) or not any(
            isinstance(item, dict) and item.get("ifname") not in (None, "lo")
            and isinstance(item.get("addr_info"), list)
            and any(addr.get("local") == source for addr in item["addr_info"]
                    if isinstance(addr, dict)) for item in addresses
        ):
            raise ValueError("Expected fixed source address is absent from a local non-loopback NIC")
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    case = "forced-" + args.case + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)
    try:
        out = new_out(args.out, case)
    except OSError as exc:
        parser.error("Use a NEW nonexistent evidence directory: " + str(exc))
    write_json(out / "runtime-config.json", config)
    result = perform(host, port, case, args.case == "stream", args.duration, out, source,
                     mode=args.case, origin_ip=ORIGIN_IP, egress_pool=tuple(config["egress_public_ips"]))
    print(json.dumps(result, indent=2))
    print("RESULT=NEEDS_REVIEW; a timeout is not proof of forced inspection or denial. Evidence:", out)


if __name__ == "__main__":
    main()
