#!/usr/bin/env python3
"""One bounded source-bound SPP egress TCP/HTTP attempt. No DNS/proxy/retry/reconnect."""

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
ORIGIN_IPS = {"origin1": "10.30.1.20", "origin2": "10.30.1.21"}
FIXTURE_ID = "azure-spp-origin-v1"
SOCKET_TIMEOUT_SECONDS = 5
FRESH_TOTAL_SECONDS = 15
STREAM_GRACE_SECONDS = 10
MAX_BODY_PREFIX_BYTES = 8192
MAX_FRAME_BYTES = 8192
REDACTED_RESPONSE_HEADERS = frozenset({
    "set-cookie", "set-cookie2", "authentication-info", "proxy-authentication-info",
    "authorization", "proxy-authorization", "location",
})
MODES = ("closed", "positive", "alternate", "stream")


def utc():
    return datetime.now(timezone.utc).isoformat()


def new_out(requested, case):
    out = Path(requested) if requested else Path.home() / "spp-evidence" / case
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


def safe_response_headers(headers):
    """Keep names/order/duplicates, not session secrets or redirect URL tokens."""
    return [[name, "[REDACTED]" if name.lower() in REDACTED_RESPONSE_HEADERS else value]
            for name, value in headers]


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
    expected = {"role", "private_ip", "app_ip", "origins", "egress_public_ips"}
    if not isinstance(config, dict) or set(config) != expected:
        raise ValueError("Configuration must contain exactly the five documented public fields")
    role = config.get("role")
    private = {"app": APP_IP, **ORIGIN_IPS}.get(role) if isinstance(role, str) else None
    if private is None or config.get("private_ip") != private or config.get("app_ip") != APP_IP:
        raise ValueError("Expected declared app/origin1/origin2 role and fixed lab addresses")
    origins = config["origins"]
    if not isinstance(origins, dict) or set(origins) != set(ORIGIN_IPS):
        raise ValueError("origins must contain exactly origin1 and origin2")
    destinations = {}
    for name, fixed in ORIGIN_IPS.items():
        entry = origins[name]
        if (not isinstance(entry, dict) or set(entry) != {"private_ip", "public_ip"}
                or entry["private_ip"] != fixed):
            raise ValueError("Each origin must contain its fixed private_ip and public_ip only")
        destinations[name] = public_ipv4(entry["public_ip"], name + " public_ip")
    if len(set(destinations.values())) != 2:
        raise ValueError("Origins require two distinct public destinations D1 and D2")
    pool = config["egress_public_ips"]
    if not isinstance(pool, list) or len(pool) > 16:
        raise ValueError("egress_public_ips must be a list of at most 16 public IPv4 addresses")
    for item in pool:
        public_ipv4(item, "egress_public_ips entry")
    if len(set(pool)) != len(pool) or set(destinations.values()).intersection(pool):
        raise ValueError("Egress pool must be unique and disjoint from both origin destinations D1/D2")
    if require_pool and not pool:
        raise ValueError("A nonempty actual approved SPP egress E pool is required before a probe")
    return role, private, destinations, tuple(pool)


def identity(row, case, origin_ip, port, path, egress_pool):
    """B reports proxy egress peer E:q; q need not equal client source port a."""
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


def perform(host, port, case, stream, duration, out, source, mode=None, *, origin_ip=ORIGIN_IPS["origin1"], egress_pool=()):
    """Internal numeric socket helper; CLI enforces global D/E and exact app A.

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
        raise ValueError("A literal IPv4 origin and nonempty expected E pool are required")
    out = Path(out)
    start = time.monotonic()
    identity_path = f"/stream/{case}" if stream else f"/probe/{case}"
    path = identity_path + (f"?seconds={duration}" if stream else "")
    total_seconds = duration + STREAM_GRACE_SECONDS if stream else FRESH_TOTAL_SECONDS
    result = {
        "started_utc": utc(), "case_id": case, "mode": mode, "requested_case": mode,
        "duration_requested": duration if stream else None, "outcome": "NEEDS_REVIEW",
        "attempted_destination": [host, port], "attempted_source_ip": source,
        "request_path": path, "request_url": f"http://{host}:{port}{path}",
        "observation": "NOT_STARTED", "block_proven": False, "provider_path_proven": False,
        "response_body_prefix_handling": "Treat response-body-prefix.bin as potentially sensitive: unexpected SSO or proxy HTML can contain tokens. Keep it private; review and redact before sharing. The helper does not transmit captured response evidence.",
        "response_header_redaction": "Values for cookies, authentication-info, authorization and Location are redacted; header names, order and duplicates remain",
        "tcp_connect_completed": False, "request_write_status": "not-started",
        "http_request_not_sent": True, "expected_fixture": FIXTURE_ID,
        "expected_source_preserved": False,
        "expected_origin_private": [origin_ip, port],
        "expected_egress_public_ips": list(egress_pool),
        "translation_model": "Client A:a -> D:80 and provider egress E:q -> D:80 may be separate HTTP proxy sessions in the external ZIA service. The Azure SPP association is control plane, not a proxy endpoint. Azure origin public-IP mapping D:80 -> B:80 is distinct. q may differ from a; one TCP sequence space is not assumed",
        "tcp_sequence_continuity_required": False,
        "socket_timeout_seconds": SOCKET_TIMEOUT_SECONDS, "total_timeout_seconds": total_seconds,
        "automatic_retry": False, "automatic_reconnect": False,
        "frames_received": 0, "stream_complete": False,
        "fixture_identity": "UNOBSERVED", "fixture_response_complete": False,
        "source_tuple_preserved_observed": False,
        "egress_translation_observed": False,
        "evidence_note": "The external ZIA service may proxy HTTP: TCP can connect and a Block action may yield HTML with HTTP 200/403, a reset, or a timeout. None alone proves a block or provider path. Correlate unique URL/case and UTC with endpoint captures, healthy origins, effective Azure routes and provider-native activity logs; do not match TCP sequences or require q=a.",
    }
    frames = []
    body_prefix = bytearray()
    body_prefix_truncated = False
    nonfixture_body = False
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
        cutoff.check()
        result["request_write_status"] = "attempting"
        # From here a failed send may be partial; never claim HTTP was not sent.
        result["http_request_not_sent"] = False
        result["request_write_started_utc"] = utc()
        write_json(out / "request-started.json", result)
        conn.request("GET", path, headers={
            "X-Lab-Case-ID": case, "User-Agent": "azure-spp-lab/" + case,
            "Connection": "close", "Cache-Control": "no-store", "Pragma": "no-cache",
        })
        result["request_write_status"] = "completed-not-proof-of-delivery"
        result["request_write_completed_utc"] = utc()
        write_json(out / "request-written.json", result)
        cutoff.check()
        response = conn.getresponse()
        result["http_status"] = response.status
        result["http_reason"] = response.reason
        result["response_headers"] = safe_response_headers(response.getheaders())
        result["response_headers_utc"] = utc()
        write_json(out / "response-headers.json", result)
        with (out / "frames.ndjson").open("x") as output:
            os.chmod(out / "frames.ndjson", 0o600)
            while True:
                cutoff.check()
                line = response.readline(MAX_FRAME_BYTES + 1)
                if not line:
                    cutoff.check()
                    reached_eof = True
                    break
                remaining = MAX_BODY_PREFIX_BYTES - len(body_prefix)
                body_prefix.extend(line[:remaining])
                body_prefix_truncated = body_prefix_truncated or len(line) > remaining
                cutoff.check()
                if len(line) > MAX_FRAME_BYTES:
                    nonfixture_body = True
                    result["body_read_stopped"] = "bounded oversized frame or non-fixture response"
                    break
                try:
                    row = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    nonfixture_body = True
                    result["body_read_stopped"] = "non-JSON response; bounded prefix retained"
                    break
                if not isinstance(row, dict) or row.get("fixture") != FIXTURE_ID:
                    nonfixture_body = True
                    result["body_read_stopped"] = "non-fixture response; bounded prefix retained"
                    break
                if len(frames) >= (duration + 3 if stream else 1):
                    raise ValueError("Too many fixture frames")
                if first_frame_at is None:
                    first_frame_at = time.monotonic()
                last_frame_at = time.monotonic()
                frames.append(row)
                output.write(json.dumps(row) + "\n")
                output.flush()
                os.fsync(output.fileno())

        if nonfixture_body and len(body_prefix) < MAX_BODY_PREFIX_BYTES:
            # A block page may be multiline HTML under status 200 or 403. Retain
            # a useful prefix, never the unbounded body, on this same socket.
            remaining = MAX_BODY_PREFIX_BYTES - len(body_prefix)
            try:
                extra = response.read(remaining + 1)
            except http.client.IncompleteRead as exc:
                extra = exc.partial
                result["body_read_stopped"] = "incomplete non-fixture body; bounded prefix retained"
            body_prefix.extend(extra[:remaining])
            body_prefix_truncated = body_prefix_truncated or len(extra) > remaining
            cutoff.check()
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
            and all(identity(row, case, origin_ip, port, identity_path, egress_pool)
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
            "note": "Origin HTTP self-report is correlation evidence, not authenticated proof of SPP traversal or proxy-leg continuity",
        }
        result["last_frame_utc"] = frames[-1].get("time_utc") if frames else None
        result["http_body_eof_observed"] = reached_eof
        result["fixture_response_complete"] = bool(
            reached_eof and not nonfixture_body and "error" not in result
            and result["fixture_identity"] == "MATCH"
        )
        result["stream_complete"] = bool(
            stream and result["fixture_response_complete"] and result["fixture_identity"] == "MATCH"
            and frames[-1].get("stream_end") is True
            and all(row.get("stream_end") is not True for row in frames[:-1])
            and all(type(row.get("frame")) is int for row in frames)
            and [row.get("frame") for row in frames] == list(range(len(frames)))
            and first_frame_at is not None and last_frame_at - first_frame_at >= duration - 1
        )
        result["response_body_prefix_bytes"] = len(body_prefix)
        result["response_body_prefix_limit"] = MAX_BODY_PREFIX_BYTES
        result["response_body_prefix_truncated"] = body_prefix_truncated
        if "http_status" in result:
            descriptor = os.open(out / "response-body-prefix.bin", os.O_WRONLY | os.O_CREAT | os.O_EXCL
                                 | getattr(os, "O_NOFOLLOW", 0), 0o600)
            with os.fdopen(descriptor, "wb") as output:
                output.write(body_prefix)
                output.flush()
                os.fsync(output.fileno())
        if result["fixture_identity"] == "MATCH":
            result["observation"] = "FIXTURE_RESPONSE" if result["fixture_response_complete"] else "PARTIAL_FIXTURE_RESPONSE"
        elif result["fixture_identity"] == "MISMATCH":
            result["observation"] = "FIXTURE_IDENTITY_MISMATCH"
        elif "http_status" in result:
            result["observation"] = "NON_FIXTURE_HTTP_RESPONSE"
        elif result.get("error_type") in ("TimeoutError", "timeout"):
            result["observation"] = "TRANSPORT_TIMEOUT"
        elif result.get("error_type") in ("ConnectionResetError", "BrokenPipeError", "RemoteDisconnected"):
            result["observation"] = "TRANSPORT_RESET_OR_CLOSED"
        else:
            result["observation"] = "ATTEMPT_FAILED"
        result["completed_utc"] = utc()
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        write_json(out / "result.json", result)
    return result


def validate_config(config, mode):
    if mode not in MODES:
        raise ValueError("Invalid lab mode; reverse flow is not supported")
    role, source, destinations, _pool = validate_public_config(config, require_pool=True)
    if role != "app":
        raise ValueError("Every public probe requires the declared fixed-address app VM")
    return source, destinations["origin2" if mode == "alternate" else "origin1"], 80


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=MODES)
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--out")
    args = parser.parse_args()
    if not 5 <= args.duration <= 180:
        parser.error("duration must be 5..180 seconds")
    try:
        config = json.loads(Path(os.environ.get("SPP_LAB_CONFIG", "/etc/azure-spp-lab.json")).read_text())
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
    case = "spp-" + args.case + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)
    try:
        out = new_out(args.out, case)
    except OSError as exc:
        parser.error("Use a NEW nonexistent evidence directory: " + str(exc))
    write_json(out / "runtime-config.json", config)
    result = perform(host, port, case, args.case == "stream", args.duration, out, source,
                     mode=args.case, origin_ip=ORIGIN_IPS["origin2" if args.case == "alternate" else "origin1"], egress_pool=tuple(config["egress_public_ips"]))
    print(json.dumps(result, indent=2))
    print("RESULT=NEEDS_REVIEW; HTTP responses, resets and timeouts do not prove SPP blocking. Evidence:", out)


if __name__ == "__main__":
    main()
