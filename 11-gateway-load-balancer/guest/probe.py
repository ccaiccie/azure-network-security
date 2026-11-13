#!/usr/bin/env python3
"""One bounded HTTP attempt from a separately approved external operator client.

No DNS, proxy, redirect following, retries or reconnects. Public C is an explicit
operator assertion, distinct from the locally bound address and ephemeral port.
"""

import argparse
import hashlib
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

BACKEND_IP = "10.20.1.20"
FIXTURE_ID = "azure-gwlb-fixture-v1"
MODES = ("closed", "positive", "alternate", "stream", "payload")
SOCKET_TIMEOUT_SECONDS = 5
FRESH_TOTAL_SECONDS = 15
STREAM_GRACE_SECONDS = 10
MAX_PAYLOAD_BYTES = 262144
MAX_BODY_PREFIX_BYTES = 8192
MAX_FRAME_BYTES = 4096
MAX_HEADER_BYTES = 8192
PAYLOAD_PATTERN = b"azure-gwlb-synthetic-payload-v1\n"
ROW_KEYS = {"fixture", "role", "case_id", "time_utc", "frame", "path", "purpose",
            "peer_ip", "peer_port", "server_ip", "server_port", "stream_end"}
IDENTITY_FIELDS = ("fixture", "role", "case_id", "server_ip", "server_port", "peer_ip", "peer_port", "path", "purpose")
SAFE_HEADERS = {"content-type", "content-length", "connection", "cache-control"} | {
    "x-lab-" + field.replace("_", "-") for field in IDENTITY_FIELDS
} | {"x-lab-body-sha256"}


def utc():
    return datetime.now(timezone.utc).isoformat()


def public_ipv4(value, label):
    if not isinstance(value, str):
        raise ValueError(label + " must be canonical numeric global IPv4")
    address = ipaddress.ip_address(value)
    if (address.version != 4 or str(address) != value or not address.is_global
            or address.is_multicast or address.is_reserved or address.is_unspecified
            or address.is_private or address.is_loopback or address.is_link_local
            or address in ipaddress.ip_network("192.0.0.0/24")
            or address in ipaddress.ip_network("192.88.99.0/24")):
        raise ValueError(label + " must be canonical numeric global unicast IPv4")
    return value


def local_ipv4(value):
    if not isinstance(value, str):
        raise ValueError("source-ip must be a numeric locally assigned IPv4 address")
    address = ipaddress.ip_address(value)
    if (address.version != 4 or str(address) != value or address.is_multicast
            or address.is_reserved or address.is_unspecified or address.is_loopback):
        raise ValueError("source-ip must be a numeric non-loopback local unicast IPv4 address")
    return value


def validate_config(config, source, mode):
    if mode not in MODES:
        raise ValueError("Unsupported probe mode")
    if not isinstance(config, dict) or set(config) != {"client_public_ip", "consumer_public_ip", "backend_ip"}:
        raise ValueError("Public config requires exactly client_public_ip, consumer_public_ip, backend_ip")
    client = public_ipv4(config["client_public_ip"], "client_public_ip C")
    destination = public_ipv4(config["consumer_public_ip"], "consumer_public_ip P")
    if client == destination or config["backend_ip"] != BACKEND_IP:
        raise ValueError("C and P must differ and backend_ip must be 10.20.1.20")
    source = local_ipv4(source)
    if source == BACKEND_IP or source == destination:
        raise ValueError("External client cannot bind the lab backend or consumer public frontend")
    return source, destination, 8081 if mode == "alternate" else 8080, client


def validate_local_nic(source):
    rows = json.loads(subprocess.run(["ip", "-j", "-4", "addr", "show"], check=True,
                                    capture_output=True, text=True, timeout=5).stdout)
    if not isinstance(rows, list) or not any(
        isinstance(row, dict) and row.get("ifname") not in (None, "lo")
        and isinstance(row.get("addr_info"), list)
        and any(isinstance(address, dict) and address.get("local") == source
                for address in row["addr_info"]) for row in rows
    ):
        raise ValueError("Explicit source-ip is absent from a local non-loopback NIC")


def new_out(requested, case):
    """Create private, new output using no-follow directory traversal.

    Existing output files, directories and symlinks are rejected. Parent symlinks
    are rejected too; no existing evidence is overwritten or automatically reused.
    """
    out = Path(requested) if requested else Path.home() / "gwlb-evidence" / case
    if ".." in out.parts:
        raise ValueError("Evidence paths must not contain parent traversal")
    out = Path(os.path.abspath(out))
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    current = os.open(out.anchor, flags)
    try:
        for component in out.parts[1:-1]:
            try:
                next_dir = os.open(component, flags, dir_fd=current)
            except FileNotFoundError:
                os.mkdir(component, mode=0o700, dir_fd=current)
                next_dir = os.open(component, flags, dir_fd=current)
            os.close(current)
            current = next_dir
        os.mkdir(out.name, mode=0o700, dir_fd=current)
        created = os.open(out.name, flags, dir_fd=current)
        try:
            os.fchmod(created, 0o700)
        finally:
            os.close(created)
    finally:
        os.close(current)
    return out


def private_file(path, binary=False):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    return os.fdopen(descriptor, "wb" if binary else "w")


def write_json(path, value):
    with private_file(path) as output:
        output.write(json.dumps(value, indent=2) + "\n")
        output.flush()
        os.fsync(output.fileno())


def safe_response_headers(headers):
    return [[name[:64], value[:256] if name.lower() in SAFE_HEADERS else "[REDACTED]"]
            for name, value in headers[:100]]


class HeaderBudget:
    def __init__(self, reader):
        self.reader = reader
        self.remaining = MAX_HEADER_BYTES

    def readline(self, size=-1):
        limit = self.remaining + 1 if size < 0 else min(size, self.remaining + 1)
        line = self.reader.readline(limit)
        self.remaining -= len(line)
        if self.remaining < 0:
            raise http.client.LineTooLong("aggregate response headers")
        return line


class BoundedResponse(http.client.HTTPResponse):
    def begin(self):
        original = self.fp
        self.fp = HeaderBudget(original)
        try:
            return super().begin()
        finally:
            self.fp = original


class TotalDeadline:
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


def valid_time(value):
    try:
        return isinstance(value, str) and datetime.fromisoformat(value).utcoffset().total_seconds() == 0
    except (TypeError, ValueError, AttributeError):
        return False


def identity(row, case, backend, port, path, public_client):
    return (isinstance(row, dict) and set(row) == ROW_KEYS
            and tuple(row.get(key) for key in ("fixture", "role", "case_id", "server_ip", "server_port", "path", "peer_ip", "purpose"))
            == (FIXTURE_ID, "backend", case, backend, port, path, public_client, "external-client-probe")
            and type(row.get("server_port")) is int and type(row.get("peer_port")) is int
            and 1 <= row["peer_port"] <= 65535 and type(row.get("frame")) is int
            and type(row.get("stream_end")) is bool and valid_time(row.get("time_utc")))


def header_identity(headers):
    row = {}
    for field in IDENTITY_FIELDS:
        values = headers.get_all("X-Lab-" + field.replace("_", "-"), [])
        if len(values) != 1:
            return None
        value = values[0]
        if field.endswith("_port"):
            if not re.fullmatch(r"[1-9][0-9]{0,4}", value) or int(value) > 65535:
                return None
            value = int(value)
        row[field] = value
    return row


def expected_payload(size):
    return (PAYLOAD_PATTERN * ((size + len(PAYLOAD_PATTERN) - 1) // len(PAYLOAD_PATTERN)))[:size]


def perform(host, port, case, mode, duration, size, out, source, *, public_client, backend_ip=BACKEND_IP):
    """Internal numeric-socket primitive. CLI enforces global C/P and exact B.

    Tests override only these internal arguments to use guarded loopback; no CLI
    option weakens address validation or places a probe on an Azure backend guest.
    """
    if mode not in MODES or type(duration) is not int or not 5 <= duration <= 180:
        raise ValueError("Mode and 5..180 second duration are required")
    if type(size) is not int or not 1 <= size <= MAX_PAYLOAD_BYTES:
        raise ValueError("bytes must be 1..262144")
    if not isinstance(case, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", case):
        raise ValueError("Invalid case ID")
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("Invalid destination port")
    for value in (host, source, public_client, backend_ip):
        if ipaddress.ip_address(value).version != 4 or str(ipaddress.ip_address(value)) != value:
            raise ValueError("All addresses must be canonical numeric IPv4")
    stream, payload = mode == "stream", mode == "payload"
    endpoint = "stream" if stream else "payload" if payload else "probe"
    identity_path = f"/{endpoint}/{case}"
    path = identity_path + (f"?seconds={duration}" if stream else f"?bytes={size}" if payload else "")
    total_seconds = duration + STREAM_GRACE_SECONDS if stream else FRESH_TOTAL_SECONDS
    start = time.monotonic()
    out = Path(out)
    result = {
        "started_utc": utc(), "case_id": case, "mode": mode, "outcome": "NEEDS_REVIEW",
        "attempted_destination": [host, port], "attempted_source_ip": source,
        "asserted_client_public_ip_C": public_client, "asserted_client_public_port": None,
        "client_public_ip_source": "Explicit operator assertion in public runtime config; not discovered by this helper",
        "backend_ip_B": backend_ip, "consumer_public_ip_P": host,
        "request_path": path, "request_url": f"http://{host}:{port}{path}",
        "expected_fixture": FIXTURE_ID, "expected_role": "backend",
        "duration_requested": duration if stream else None, "payload_bytes_requested": size if payload else None,
        "socket_timeout_seconds": SOCKET_TIMEOUT_SECONDS, "total_timeout_seconds": total_seconds,
        "tcp_connect_completed": False, "http_request_not_sent": True, "request_write_status": "not-started",
        "automatic_retry": False, "automatic_reconnect": False, "redirects_followed": False,
        "dns_used": False, "proxies_used": False, "observation": "NOT_STARTED",
        "fixture_identity": "UNOBSERVED", "fixture_response_complete": False, "stream_complete": False,
        "body_size_verified": False, "body_sha256_verified": False,
        "block_proven": False, "gwlb_path_proven": False, "packet_fragmentation_proven": False,
        "source_port_mapping_inferred": False,
        "tuple_note": "Local bind L:l may be behind NAT. C is asserted, its public source port is unknown. Backend-reported C:c is separate evidence; never infer c=l or invent a NAT mapping. NVA inner translation boundaries require captures.",
        "payload_note": "A bounded larger TCP response observes byte delivery and loss only; it does not prove MTU, PMTUD or packet fragmentation.",
        "privacy_note": "Evidence stays local. Files are private, headers outside the safe identity/HTTP allowlist are redacted, and raw body prefix is limited to 8192 bytes. Unexpected responses can still contain secrets; review/redact before sharing.",
        "evidence_note": "HTTP success, denial, reset or timeout alone never proves GWLB path or policy. Correlate the unique case, both NVA tunnel captures/counters, backend logs, chain, healthy services and effective NSGs/routes.",
    }
    frames, prefix = [], bytearray()
    digest = hashlib.sha256()
    body_bytes = 0
    reached_eof = False
    valid_body = True
    first_frame_at = last_frame_at = None
    response = cutoff = header_row = None
    content_length = None
    conn = http.client.HTTPConnection(host, port, timeout=SOCKET_TIMEOUT_SECONDS)
    conn.auto_open = 0
    conn.response_class = BoundedResponse

    def absorb(chunk):
        nonlocal body_bytes
        body_bytes += len(chunk)
        digest.update(chunk)
        prefix.extend(chunk[:max(0, MAX_BODY_PREFIX_BYTES - len(prefix))])

    try:
        conn.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.sock.settimeout(SOCKET_TIMEOUT_SECONDS)
        cutoff = TotalDeadline(conn.sock, total_seconds)
        cutoff.start()
        cutoff.check()
        conn.sock.bind((source, 0))
        result["attempted_local"] = list(conn.sock.getsockname())
        if result["attempted_local"][0] != source or not 1 <= result["attempted_local"][1] <= 65535:
            raise ValueError("Bound source tuple does not match explicit source-ip")
        result["connect_attempt_utc"] = utc()
        # Durable evidence before any SYN, including intentionally denied cases.
        write_json(out / "connection.json", result)
        cutoff.check()
        conn.sock.connect((host, port))
        result["tcp_connect_completed"] = True
        result["connected_utc"] = utc()
        result["client_local"] = list(conn.sock.getsockname())
        result["client_remote"] = list(conn.sock.getpeername())
        write_json(out / "connected.json", result)
        if result["client_local"] != result["attempted_local"] or result["client_remote"] != [host, port]:
            raise ValueError("Connected tuple differs from the attempted socket tuple")
        cutoff.check()
        result["request_write_status"] = "attempting"
        result["http_request_not_sent"] = False
        result["request_write_started_utc"] = utc()
        write_json(out / "request-started.json", result)
        conn.request("GET", path, headers={
            "X-Lab-Case-ID": case, "User-Agent": "azure-gwlb-external-client/" + case,
            "Connection": "close", "Cache-Control": "no-store", "Pragma": "no-cache",
        })
        result["request_write_status"] = "completed-not-proof-of-delivery"
        result["request_write_completed_utc"] = utc()
        write_json(out / "request-written.json", result)
        cutoff.check()
        response = conn.getresponse()
        result["http_status"] = response.status
        result["response_headers"] = safe_response_headers(response.getheaders())
        result["response_headers_utc"] = utc()
        write_json(out / "response-headers.json", result)
        header_row = header_identity(response.headers)
        lengths = response.headers.get_all("Content-Length", [])
        if lengths:
            if len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,6}", lengths[0]):
                raise ValueError("Invalid or duplicate Content-Length")
            content_length = int(lengths[0])
        if response.headers.get("Transfer-Encoding") is not None:
            raise ValueError("Controlled fixture does not use Transfer-Encoding")
        if content_length is not None and content_length > MAX_PAYLOAD_BYTES:
            raise ValueError("Response body length exceeds 256 KiB bound")
        if payload:
            while body_bytes <= MAX_PAYLOAD_BYTES:
                cutoff.check()
                chunk = response.read(min(4096, MAX_PAYLOAD_BYTES + 1 - body_bytes))
                if not chunk:
                    cutoff.check()
                    reached_eof = True
                    break
                absorb(chunk)
                cutoff.check()
                if body_bytes > MAX_PAYLOAD_BYTES:
                    raise ValueError("Response exceeded body limit")
        else:
            with private_file(out / "frames.ndjson") as frame_file:
                while True:
                    cutoff.check()
                    line = response.readline(MAX_FRAME_BYTES + 1)
                    if not line:
                        cutoff.check()
                        reached_eof = True
                        break
                    absorb(line)
                    cutoff.check()
                    if len(line) > MAX_FRAME_BYTES or body_bytes > MAX_PAYLOAD_BYTES:
                        raise ValueError("Response exceeded frame/body limit")
                    try:
                        row = json.loads(line)
                    except (ValueError, UnicodeDecodeError):
                        valid_body = False
                        result["body_read_stopped"] = "Non-JSON response; bounded private prefix retained"
                        break
                    if not isinstance(row, dict) or set(row) != ROW_KEYS:
                        valid_body = False
                        result["body_read_stopped"] = "Unexpected fixture schema; bounded private prefix retained"
                        break
                    if len(frames) >= (duration + 2 if stream else 1):
                        raise ValueError("Too many fixture frames")
                    if first_frame_at is None:
                        first_frame_at = time.monotonic()
                    last_frame_at = time.monotonic()
                    frames.append(row)
                    frame_file.write(json.dumps(row) + "\n")
                    frame_file.flush()
                    os.fsync(frame_file.fileno())
    except (OSError, ValueError, http.client.HTTPException) as exc:
        result["error_type"] = "TimeoutError" if cutoff and cutoff.expired.is_set() else type(exc).__name__
        result["error"] = "Total bounded client window exceeded" if cutoff and cutoff.expired.is_set() else str(exc)[:256]
        result["error_utc"] = utc()
    except BaseException as exc:
        result["error_type"] = type(exc).__name__
        result["error"] = "Probe interrupted; no reconnect attempted"
        result["error_utc"] = utc()
        raise
    finally:
        if cutoff is not None:
            cutoff.stop()
        if response is not None:
            response.close()
        conn.close()
        peers = {(row["peer_ip"], row["peer_port"]) for row in frames
                 if isinstance(row.get("peer_ip"), str) and type(row.get("peer_port")) is int}
        expected_header = {"fixture": FIXTURE_ID, "role": "backend", "case_id": case,
                           "server_ip": backend_ip, "server_port": port, "peer_ip": public_client,
                           "path": identity_path, "purpose": "external-client-probe"}
        header_match = bool(header_row and all(header_row.get(key) == value for key, value in expected_header.items()))
        if payload and header_match:
            peers.add((header_row["peer_ip"], header_row["peer_port"]))
        fixture_match = bool(result.get("http_status") == 200 and header_match and len(peers) == 1
                             and (payload or (frames and all(identity(row, case, backend_ip, port, identity_path, public_client) for row in frames)))
                             and (not header_row or (header_row["peer_ip"], header_row["peer_port"]) in peers))
        result["fixture_identity"] = "MATCH" if fixture_match else "MISMATCH" if frames or header_row else "UNOBSERVED"
        result["frames_received"] = len(frames)
        result["observed_backend_peer_tuples"] = [list(peer) for peer in sorted(peers)]
        result["observed_backend_server_tuple"] = [header_row["server_ip"], header_row["server_port"]] if header_row else None
        result["backend_reported_source_matches_asserted_C"] = bool(fixture_match)
        result["public_source_port_verified"] = False
        result["http_body_eof_observed"] = reached_eof
        result["response_body_bytes_observed"] = body_bytes
        result["response_body_sha256_observed"] = digest.hexdigest()
        result["response_content_length"] = content_length
        result["response_body_prefix_bytes"] = len(prefix)
        result["response_body_prefix_limit"] = MAX_BODY_PREFIX_BYTES
        result["response_body_prefix_truncated"] = body_bytes > len(prefix) or not reached_eof
        result["body_size_verified"] = bool(reached_eof and content_length is not None and body_bytes == content_length)
        response_hashes = response.headers.get_all("X-Lab-Body-SHA256", []) if response is not None else []
        result["body_sha256_verified"] = bool(reached_eof and len(response_hashes) == 1 and re.fullmatch(r"[0-9a-f]{64}", response_hashes[0]) and digest.hexdigest() == response_hashes[0])
        if payload:
            result["payload_pattern_verified"] = bool(reached_eof and body_bytes == size and digest.hexdigest() == hashlib.sha256(expected_payload(size)).hexdigest())
        result["fixture_response_complete"] = bool(fixture_match and reached_eof and valid_body and "error" not in result
            and (stream or (result["body_size_verified"] and result["body_sha256_verified"]))
            and (not payload or result.get("payload_pattern_verified"))
            and (payload or stream or (len(frames) == 1 and frames[0]["frame"] == 0 and frames[0]["stream_end"] is False)))
        result["stream_complete"] = bool(stream and result["fixture_response_complete"] and frames
            and frames[-1]["stream_end"] is True and all(row["stream_end"] is False for row in frames[:-1])
            and [row["frame"] for row in frames] == list(range(len(frames)))
            and first_frame_at is not None and last_frame_at - first_frame_at >= duration - 1)
        if stream and not result["stream_complete"]:
            result["fixture_response_complete"] = False
        if "http_status" in result:
            with private_file(out / "response-body-prefix.bin", binary=True) as output:
                output.write(prefix)
                output.flush()
                os.fsync(output.fileno())
        if fixture_match:
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=MODES)
    parser.add_argument("--config", required=True, help="Public JSON config for the approved external client")
    parser.add_argument("--source-ip", required=True, help="Explicit locally assigned bind IP; may be private behind NAT")
    parser.add_argument("--out", help="New nonexistent private evidence directory")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--bytes", type=int, default=MAX_PAYLOAD_BYTES, dest="size")
    args = parser.parse_args()
    if not 5 <= args.duration <= 180 or not 1 <= args.size <= MAX_PAYLOAD_BYTES:
        parser.error("duration must be 5..180 seconds and bytes must be 1..262144")
    try:
        config = json.loads(Path(args.config).read_text())
        source, host, port, public_client = validate_config(config, args.source_ip, args.case)
        validate_local_nic(source)
        case = "gwlb-" + args.case + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)
        out = new_out(args.out, case)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    write_json(out / "runtime-config.json", config)
    result = perform(host, port, case, args.case, args.duration, args.size, out, source,
                     public_client=public_client, backend_ip=config["backend_ip"])
    print(json.dumps(result, indent=2))
    print("RESULT=NEEDS_REVIEW; correlate policy, chain, captures and backend evidence. Evidence:", out)


if __name__ == "__main__":
    main()
